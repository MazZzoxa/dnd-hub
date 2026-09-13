import 'package:flutter_test/flutter_test.dart';

import 'package:dnd_hub/data/import/url/public_content_importer.dart';
import 'package:dnd_hub/data/models/library_item_model.dart';

String _url(String path) => 'https://' + String.fromCharCodes(const [100, 110, 100, 46, 115, 117]) + path;

void main() {
  group('PublicContentImporter', () {
    test('recognizes supported content URLs', () {
      expect(
        PublicContentImporter.matches(Uri.parse(_url('/spells/227-web/'))),
        isTrue,
      );
      expect(
        PublicContentImporter.matches(Uri.parse(_url('/items/142-vorpal-sword/'))),
        isTrue,
      );
      expect(
        PublicContentImporter.matches(Uri.parse(_url('/feats/103-alert/'))),
        isTrue,
      );
      expect(
        PublicContentImporter.matches(Uri.parse('https://example.com/spells/227-web/')),
        isFalse,
      );
    });

    test('parses a spell into a library object', () {
      const html = '''
        <html><body><main>
          <h1>Паутина — Заклинания</h1>
          <p>2 уровень, вызов</p>
          <p>Время накладывания: 1 действие</p>
          <p>Дистанция: 60 футов</p>
          <p>Компоненты: В, С, М (кусок паутины)</p>
          <p>Длительность: Концентрация, вплоть до 1 часа</p>
          <p>Классы: волшебник, чародей</p>
          <p>Подклассы: отсутствуют</p>
          <p>Вы вызываете сеть липкой паутины.</p>
        </main></body></html>
      ''';

      final item = PublicContentImporter.parse(
        html,
        _url('/spells/227-web/'),
      );

      expect(item, isNotNull);
      expect(item!.type, LibraryItemType.spell);
      expect(item.name, 'Паутина');
      expect(item.data['level'], 2);
      expect(item.data['school'], 'вызов');
      expect(item.data['castingTime'], '1 действие');
      expect(item.data['range'], '60 футов');
      expect(item.data['components'], 'В, С, М (кусок паутины)');
      expect(item.data['description'], contains('липкой паутины'));
      expect(item.sourceType, LibrarySourceType.imported);
      expect(item.sourceUrl, _url('/spells/227-web/'));
    });

    test('parses the Needler Pistol page shape without duplication', () {
      const html = '''
        <html><body><main>
          <h1>Игломет [Needler Pistol]QIS — Магические предметы</h1>
          <li><p>Оружие</p></li>
          <p>Чужеродный пистолет напоминает колбу с сотами из трубок, торчащих из передней части. Оружие питается от батареи, хранящейся в основании колбы. Если поместить в пистолет полную батарею, он получит 10 зарядов.</p>
          <p>Пока вы держите пистолет, действием вы можете потратить один из его зарядов, чтобы выпустить из него град светящихся, похожих на иглы дротиков в 15-футовом конусе. Каждое существо в этой области должно совершить спасбросок Ловкости Сл 15, получая 8к4 колющего урона при провале и половину урона при успехе.</p>
          <p>Замена батареи. Пока у пистолета остаются заряды, его батарею нельзя извлечь. Когда в нем останется 0 зарядов, вы можете заменить батарею на новую действием или бонусным действием.</p>
        </main></body></html>
      ''';

      final item = PublicContentImporter.parse(
        html,
        _url('/items/10775-needler-pistol/'),
      );

      expect(item, isNotNull);
      expect(item!.name, 'Игломет');
      expect(item.data['category'], 'Weapons');
      expect(item.data['details'], 'Оружие');
      expect(item.data['rarity'], '');
      expect(item.data['requiresAttunement'], isFalse);
      final description = item.data['description'] as String;
      expect(description.split('Замена батареи.').length, 2);
      expect(description, contains('8к4 колющего урона'));
    });

    test('parses an item and detects attunement', () {
      const html = '''
        <html><body><main>
          <h1>Меч головоруб — Магические предметы</h1>
          <p>Оружие (любой меч), легендарное (требуется настройка)</p>
          <p>Рекомендованная стоимость: от 50 001 зм</p>
          <p>Вы получаете бонус +3 к броскам атаки и урона.</p>
        </main></body></html>
      ''';

      final item = PublicContentImporter.parse(
        html,
        _url('/items/142-vorpal-sword/'),
      );

      expect(item, isNotNull);
      expect(item!.type, LibraryItemType.item);
      expect(item.name, 'Меч головоруб');
      expect(item.data['category'], 'Weapons');
      expect(item.data['requiresAttunement'], isTrue);
      expect(item.data['price'], contains('50 001'));
      expect(item.data['description'], contains('бонус +3'));
    });

    test('parses a feat as an ability', () {
      const html = '''
        <html><body><main>
          <h1>Бдительный — Черты</h1>
          <p>Вы всегда готовы к опасностям.</p>
          <p>Вы получаете бонус +5 к проверкам инициативы.</p>
        </main></body></html>
      ''';

      final item = PublicContentImporter.parse(
        html,
        _url('/feats/103-alert/'),
      );

      expect(item, isNotNull);
      expect(item!.type, LibraryItemType.ability);
      expect(item.name, 'Бдительный');
      expect(item.data['category'], 'Черта');
      expect(item.data['description'], contains('бонус +5'));
    });
  });
}
