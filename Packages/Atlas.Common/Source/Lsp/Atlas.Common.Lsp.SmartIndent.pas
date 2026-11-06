unit Atlas.Common.Lsp.SmartIndent;

// Einrückung beim Tippen (#1827) über das Protokoll: Befehl
// atlas.server.smartIndent. Das Plugin schickt vorher den Puffer.
//   - [uri, line, options]: nach Enter in der neuen Zeile line (0-basiert).
//     options sind die FormattingOptions des Editors ({tabSize,
//     insertSpaces}); darüber gelten .editorconfig und "format". Antwort
//     {"edits": TextEdit[], "cursor": Position} oder null, wenn Atlas dort
//     nichts bestimmt oder "smartIndent" aus ist.
//   - [uri, line, options, "column"]: nur die Spalte einer Anweisung am
//     Anfang von line (Einfügen, #1832). Antwort {"column": Zahl} oder null.
// Die Logik liegt in Atlas.Common.Editing.SmartIndent.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Editing.SmartIndent;

type
  /// <summary>Optionen für AUri mit den Editor-Optionen AEditorOptions (nil = keine); False, wenn "smartIndent"
  /// für die Datei aus ist.</summary>
  TSmartIndentOptionsFunc = reference to function(const AUri: string; const AEditorOptions: TJSONValue;
    out AOptions: TSmartIndentOptions): Boolean;

  TLspSmartIndent = class
  public const
    Command = 'atlas.server.smartIndent';
    /// <summary>Viertes Argument: nur die Spalte.</summary>
    ColumnMode = 'column';
  public
    /// <summary>Optionen aus den Einstellungen ASettings und dem Formatstil AStyle; False bei abgeschaltetem
    /// Hauptschalter.</summary>
    class function OptionsFrom(const ASettings: TSmartIndentSettings; const AStyle: TFormatStyle;
      out AOptions: TSmartIndentOptions): Boolean; static;
    /// <summary>Antwort auf AArguments (siehe oben); der Aufrufer übernimmt sie. Ungültige Argumente ergeben
    /// EArgumentException.</summary>
    class function Execute(const AStore: IDocumentStore; const AOptionsFor: TSmartIndentOptionsFunc;
      const AArguments: TJSONArray): TJSONValue; static;
  end;

implementation

uses
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TSmartIndentText = (ArgumentsUriAndLineMissing);

const
  cTexts: array[TSmartIndentText] of TAtlasText = (
    (De: 'Argumente "uri" und "line" fehlen'; En: 'Arguments "uri" and "line" missing'));

{$SCOPEDENUMS OFF}

class function TLspSmartIndent.OptionsFrom(const ASettings: TSmartIndentSettings; const AStyle: TFormatStyle;
  out AOptions: TSmartIndentOptions): Boolean;
begin
  AOptions := TSmartIndentOptions.Default;
  AOptions.AfterEnter := ASettings.AfterEnter;
  AOptions.OutdentClosers := ASettings.OutdentClosers;
  AOptions.SplitStrings := ASettings.SplitStrings;
  if SameText(ASettings.SplitStringsIndent, 'align') then
  begin
    AOptions.StringContinuation := TStringContinuation.Align;
  end;
  AOptions.IndentSize := AStyle.IndentSize;
  AOptions.UseTabs := AStyle.UseTabs;
  Result := ASettings.Enabled;
end;

/// <summary>Änderungen und Schreibmarke als JSON.</summary>
function ResultJson(const AResult: TSmartIndentResult): TJSONObject;
var
  mEdits: TJSONArray;
  mEdit: TTextEdit;
  mItem: TJSONObject;
begin
  mEdits := TJSONArray.Create;
  for mEdit in AResult.Edits do
  begin
    mItem := TJSONObject.Create;
    mItem.AddPair('range', TLspPositions.RangeToJson(mEdit.Range));
    mItem.AddPair('newText', mEdit.NewText);
    mEdits.AddElement(mItem);
  end;
  Result := TJSONObject.Create;
  Result.AddPair('edits', mEdits);
  Result.AddPair('cursor', TLspPositions.PositionToJson(AResult.Cursor));
end;

/// <summary>Spalte einer Anweisung am Anfang von ALine als JSON; null, wenn Atlas sie nicht bestimmt.</summary>
function ColumnJson(const AText: string; ALine: Integer; const AOptions: TSmartIndentOptions): TJSONValue;
var
  mColumn: Integer;
begin
  if not TSmartIndent.ColumnAt(AText, ALine, AOptions.IndentSize, mColumn) then
  begin
    Exit(TJSONNull.Create);
  end;
  Result := TJSONObject.Create(TJSONPair.Create('column', TJSONNumber.Create(mColumn)));
end;

class function TLspSmartIndent.Execute(const AStore: IDocumentStore; const AOptionsFor: TSmartIndentOptionsFunc;
  const AArguments: TJSONArray): TJSONValue;
var
  mUri: string;
  mLine: Integer;
  mDocument: ITextDocument;
  mEditorOptions: TJSONValue;
  mOptions: TSmartIndentOptions;
  mResult: TSmartIndentResult;
begin
  if (AArguments = nil) or (AArguments.Count < 2) or not (AArguments.Items[1] is TJSONNumber) then
  begin
    raise EArgumentException.Create(cTexts[TSmartIndentText.ArgumentsUriAndLineMissing].Text);
  end;
  mUri := AArguments.Items[0].Value;
  mLine := TJSONNumber(AArguments.Items[1]).AsInt;
  mEditorOptions := nil;
  if AArguments.Count > 2 then
  begin
    mEditorOptions := AArguments.Items[2];
  end;
  if not AStore.TryGet(mUri, mDocument) or not AOptionsFor(mUri, mEditorOptions, mOptions) then
  begin
    Exit(TJSONNull.Create);
  end;
  if (AArguments.Count > 3) and (AArguments.Items[3].Value = ColumnMode) then
  begin
    Exit(ColumnJson(mDocument.Text, mLine, mOptions));
  end;
  if not TSmartIndent.AfterEnter(mDocument.Text, mLine, mOptions, mResult) then
  begin
    Exit(TJSONNull.Create);
  end;
  Result := ResultJson(mResult);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.SmartIndent', cTexts);

end.
