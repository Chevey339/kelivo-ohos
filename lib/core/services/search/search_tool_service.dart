import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'search_service.dart';
import '../../providers/settings_provider.dart';

class SearchToolService {
  static const String toolName = 'search_web';
  static const String toolDescription = 'Search the web for information';
  
  static Map<String, dynamic> getToolDefinition() {
    return {
      'type': 'function',
      'function': {
        'name': toolName,
        'description': toolDescription,
        'parameters': {
          'type': 'object',
          'properties': {
            'query': {
              'type': 'string',
              'description': 'The search query to look up online',
            },
          },
          'required': ['query'],
        },
      },
    };
  }
  
  static Future<String> executeSearch(
    String query,
    SettingsProvider settings,
  ) async {
    try {
      // Get selected search service
      final services = settings.searchServices;
      if (services.isEmpty) {
        return jsonEncode({
          'error': 'No search services configured',
        });
      }
      
      final selectedIndex = settings.searchServiceSelected.clamp(0, services.length - 1);
      final service = SearchService.getService(services[selectedIndex]);
      
      // Execute search
      final result = await service.search(
        query: query,
        commonOptions: settings.searchCommonOptions,
        serviceOptions: services[selectedIndex],
      );
      
      // Add unique IDs to each result item
      final itemsWithIds = result.items.asMap().entries.map((entry) {
        final item = entry.value;
        item.id = const Uuid().v4().substring(0, 6);
        item.index = entry.key + 1;
        return item;
      }).toList();
      
      // Return formatted result
      return jsonEncode({
        if (result.answer != null) 'answer': result.answer,
        'items': itemsWithIds.map((item) => item.toJson()).toList(),
      });
    } catch (e) {
      return jsonEncode({
        'error': 'Search failed: $e',
      });
    }
  }
  
  static String getSystemPrompt() {
    return '''
## search_web 工具使用说明

当用户询问需要实时信息或最新数据的问题时，使用 search_web 工具进行搜索。

### 引用格式
- 搜索结果中会包含index(搜索结果序号)和id(搜索结果唯一标识符)，引用格式为：
  `具体的引用内容 [citation](index:id)`
- **引用必须紧跟在相关内容之后**，在标点符号后面，不得延后到回复结尾
- 正确格式：`... [citation](index:id)` `... [citation](index:id) [citation](index:id)`

### 使用规范
1. **使用时机**
   - 用户询问最新新闻、事件、数据
   - 需要查证事实信息
   - 需要获取技术文档、API信息等
   
2. **引用要求**
   - 使用搜索结果时必须标注引用来源
   - 每个引用的事实都要紧跟 [citation](index:id) 标记
   - 不要将所有引用集中在回答末尾

3. **回答格式示例**
   ✅ 正确：
   - 据最新报道，该事件发生在昨天下午。[citation](1:a1b2c3)
   - 技术文档显示该功能需要版本3.0以上。[citation](2:d4e5f6) 具体配置步骤如下...[citation](3:g7h8i9)
   
   ❌ 错误：
   - 据最新报道，该事件发生在昨天下午。技术文档显示该功能需要版本3.0以上。
     [citation](1:a1b2c3) [citation](2:d4e5f6)
''';
  }
}