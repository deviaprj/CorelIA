/// Types d'actions navigateur que l'extension Chrome peut exécuter.
enum BrowserActionType {
  openUrl('OPEN_URL'),
  navigateBack('NAVIGATE_BACK'),
  navigateForward('NAVIGATE_FORWARD'),
  getPageContent('GET_PAGE_CONTENT'),
  summarizePage('SUMMARIZE_PAGE'),
  extractText('EXTRACT_TEXT'),
  extractLinks('EXTRACT_LINKS'),
  extractTables('EXTRACT_TABLES'),
  extractForms('EXTRACT_FORMS'),
  extractMedia('EXTRACT_MEDIA'),
  pageMetadata('PAGE_METADATA'),
  clickElement('CLICK_ELEMENT'),
  fillForm('FILL_FORM'),
  autoFillPage('AUTOFILL_PAGE'),
  scroll('SCROLL'),
  screenshot('SCREENSHOT'),
  highlightElement('HIGHLIGHT_ELEMENT'),
  waitForSelector('WAIT_FOR_SELECTOR'),
  getElementInfo('GET_ELEMENT_INFO'),
  download('DOWNLOAD'),
  saveAsPdf('SAVE_AS_PDF');

  const BrowserActionType(this.value);
  final String value;

  static BrowserActionType fromString(String value) {
    return BrowserActionType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => BrowserActionType.getPageContent,
    );
  }
}

/// Requête d'action navigateur envoyée depuis Flutter vers l'extension.
class BrowserAction {
  static int _counter = 0;

  final String actionId;
  final BrowserActionType action;
  final Map<String, dynamic> params;

  BrowserAction({
    required this.action,
    required this.params,
  }) : actionId = '${DateTime.now().millisecondsSinceEpoch}_${++_counter}';

  Map<String, dynamic> toJson() => {
        'actionId': actionId,
        'action': action.value,
        'params': params,
      };
}

/// Résultat d'une action navigateur retourné par l'extension.
class BrowserActionResult {
  final String actionId;
  final BrowserActionType action;
  final bool success;
  final Map<String, dynamic>? data;
  final String? error;

  const BrowserActionResult({
    required this.actionId,
    required this.action,
    required this.success,
    this.data,
    this.error,
  });

  factory BrowserActionResult.fromJson(Map<String, dynamic> json) =>
      BrowserActionResult(
        actionId: json['actionId'] as String? ?? '',
        action: BrowserActionType.fromString(json['action'] as String? ?? ''),
        success: json['success'] as bool? ?? false,
        data: json['data'] as Map<String, dynamic>?,
        error: json['error'] as String?,
      );

  @override
  String toString() =>
      'BrowserActionResult($actionId, ${action.value}, success=$success${error != null ? ', error=$error' : ''})';
}