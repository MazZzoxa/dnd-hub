#ifndef NOMINMAX
#define NOMINMAX
#endif

#include "windows_ocr.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <algorithm>
#include <memory>
#include <string>
#include <utility>
#include <stdexcept>
#include <vector>

#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Globalization.h>
#include <winrt/Windows.Graphics.Imaging.h>
#include <winrt/Windows.Media.Ocr.h>
#include <winrt/Windows.Storage.Streams.h>

namespace {
namespace imaging = winrt::Windows::Graphics::Imaging;
namespace ocr = winrt::Windows::Media::Ocr;
namespace streams = winrt::Windows::Storage::Streams;
namespace globalization = winrt::Windows::Globalization;

struct Candidate {
  std::string text;
  int score = -1;
};

int ScoreText(const std::string& text) {
  int letters = 0;
  int digits = 0;
  int cyrillic = 0;
  int latin = 0;

  // Decode UTF-8 just enough to classify Latin / Cyrillic code points.
  for (size_t i = 0; i < text.size();) {
    unsigned int cp = 0;
    const unsigned char lead = static_cast<unsigned char>(text[i]);
    size_t width = 1;
    if ((lead & 0x80) == 0) {
      cp = lead;
    } else if ((lead & 0xE0) == 0xC0 && i + 1 < text.size()) {
      cp = (lead & 0x1F) << 6;
      cp |= static_cast<unsigned char>(text[i + 1]) & 0x3F;
      width = 2;
    } else if ((lead & 0xF0) == 0xE0 && i + 2 < text.size()) {
      cp = (lead & 0x0F) << 12;
      cp |= (static_cast<unsigned char>(text[i + 1]) & 0x3F) << 6;
      cp |= static_cast<unsigned char>(text[i + 2]) & 0x3F;
      width = 3;
    } else if ((lead & 0xF8) == 0xF0 && i + 3 < text.size()) {
      cp = (lead & 0x07) << 18;
      cp |= (static_cast<unsigned char>(text[i + 1]) & 0x3F) << 12;
      cp |= (static_cast<unsigned char>(text[i + 2]) & 0x3F) << 6;
      cp |= static_cast<unsigned char>(text[i + 3]) & 0x3F;
      width = 4;
    } else {
      ++i;
      continue;
    }
    i += width;

    if (cp >= '0' && cp <= '9') ++digits;
    if ((cp >= 'A' && cp <= 'Z') || (cp >= 'a' && cp <= 'z')) {
      ++letters;
      ++latin;
    }
    if (cp >= 0x0400 && cp <= 0x052F) {
      ++letters;
      ++cyrillic;
    }
  }

  int score = letters + digits / 2;
  if (cyrillic >= 5) score += cyrillic * 2 + 60;
  if (latin >= 5) score += latin / 4;
  return score;
}

std::string RecognizeWithEngine(const ocr::OcrEngine& engine,
                                const std::vector<uint8_t>& bytes) {
  auto stream = streams::InMemoryRandomAccessStream();
  auto writer = streams::DataWriter(stream.GetOutputStreamAt(0));
  writer.WriteBytes(winrt::array_view<const uint8_t>(bytes));
  writer.StoreAsync().get();
  writer.FlushAsync().get();
  writer.DetachStream();
  stream.Seek(0);

  auto decoder = imaging::BitmapDecoder::CreateAsync(stream).get();
  auto bitmap = decoder.GetSoftwareBitmapAsync().get();
  if (bitmap.BitmapPixelFormat() != imaging::BitmapPixelFormat::Bgra8 ||
      bitmap.BitmapAlphaMode() != imaging::BitmapAlphaMode::Premultiplied) {
    bitmap = imaging::SoftwareBitmap::Convert(
        bitmap, imaging::BitmapPixelFormat::Bgra8,
        imaging::BitmapAlphaMode::Premultiplied);
  }

  auto result = engine.RecognizeAsync(bitmap).get();
  std::string output;
  for (const auto& line : result.Lines()) {
    std::string line_text;
    for (const auto& word : line.Words()) {
      const auto word_text = winrt::to_string(word.Text());
      if (!line_text.empty()) line_text.push_back(' ');
      line_text += word_text;
    }
    if (line_text.empty()) continue;
    if (!output.empty()) output.push_back('\n');
    output += line_text;
  }
  return output;
}


class WindowsOcrBridge {
 public:
  WindowsOcrBridge() {
    // Prefer the user's installed OCR language. For character sheets we also
    // probe Russian and English when their Windows OCR language packs exist.
    try {
      user_engine_ = ocr::OcrEngine::TryCreateFromUserProfileLanguages();
    } catch (...) {
      user_engine_ = nullptr;
    }
    try {
      ru_engine_ = ocr::OcrEngine::TryCreateFromLanguage(
          globalization::Language(L"ru-RU"));
    } catch (...) {
      ru_engine_ = nullptr;
    }
    try {
      en_engine_ = ocr::OcrEngine::TryCreateFromLanguage(
          globalization::Language(L"en-US"));
    } catch (...) {
      en_engine_ = nullptr;
    }
  }

  std::string Recognize(const std::vector<uint8_t>& bytes) {
    std::vector<Candidate> candidates;

    AddCandidate(user_engine_, bytes, &candidates);
    AddCandidate(ru_engine_, bytes, &candidates);
    AddCandidate(en_engine_, bytes, &candidates);

    if (candidates.empty()) {
      throw std::runtime_error("На Windows не найдено доступное OCR-языковое ядро. Установите языковой пакет OCR в Windows.");
    }

    const auto best = std::max_element(
        candidates.begin(), candidates.end(),
        [](const Candidate& a, const Candidate& b) { return a.score < b.score; });
    return best->text;
  }

 private:
  void AddCandidate(const ocr::OcrEngine& engine,
                    const std::vector<uint8_t>& bytes,
                    std::vector<Candidate>* candidates) {
    if (!engine) return;
    try {
      const auto text = RecognizeWithEngine(engine, bytes);
      if (text.empty()) return;
      candidates->push_back({text, ScoreText(text)});
    } catch (...) {
      // One unavailable language or a bad recognition should not prevent other
      // available OCR engines from being tried.
    }
  }

  ocr::OcrEngine user_engine_{nullptr};
  ocr::OcrEngine ru_engine_{nullptr};
  ocr::OcrEngine en_engine_{nullptr};
};

}  // namespace

void RegisterWindowsOcr(flutter::FlutterEngine* engine) {
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      engine->messenger(), "dnd_hub/windows_ocr",
      &flutter::StandardMethodCodec::GetInstance());
  auto bridge = std::make_shared<WindowsOcrBridge>();

  channel->SetMethodCallHandler(
      [bridge](const auto& call,
               std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() != "recognize") {
          result->NotImplemented();
          return;
        }

        const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
        if (!args) {
          result->Error("INVALID_ARGUMENT", "Аргументы OCR отсутствуют.");
          return;
        }
        const auto it = args->find(flutter::EncodableValue("imageBytes"));
        if (it == args->end()) {
          result->Error("INVALID_ARGUMENT", "imageBytes отсутствует.");
          return;
        }

        try {
          const auto bytes = std::get<std::vector<uint8_t>>(it->second);
          const auto text = bridge->Recognize(bytes);
          result->Success(flutter::EncodableValue(text));
        } catch (const winrt::hresult_error& e) {
          result->Error("OCR_FAILED", winrt::to_string(e.message()));
        } catch (const std::exception& e) {
          result->Error("OCR_FAILED", e.what());
        } catch (...) {
          result->Error("OCR_FAILED", "Неизвестная ошибка Windows OCR.");
        }
      });

  // Keep the channel alive for the engine lifetime. The engine takes ownership
  // of the plugin registration, while the shared bridge remains captured by
  // the channel handler.
  channel.release();
}
