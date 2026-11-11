unit Atlas.Common.Mcp.ExtractTools;

// MCP-Werkzeug extract_method (#2054): „Methode extrahieren“ für die ganzen Zeilen startLine..endLine einer Unit,
// mit Wunschname und auf Wunsch samt textgleicher Stellen der Unit (replaceDuplicates). Die Logik liegt in
// Atlas.Common.Editing.Extract; geschrieben wird über TMcpEditTools.Apply wie bei apply_code_action (dryRun zeigt
// den Diff, offene Dateien gehen über das Plugin als ein Rückgängig-Schritt).

interface

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Lsp.References,
  Atlas.Common.Mcp.EditTools;

type
  /// <summary>Eingaben von extract_method.</summary>
  TMcpExtractRequest = record
    FileName: string;
    /// <summary>Erste und letzte Zeile der Anweisungen, ab 1.</summary>
    StartLine: Integer;
    EndLine: Integer;
    /// <summary>Name der neuen Methode; '' ExtractedMethod.</summary>
    Name: string;
    ReplaceDuplicates: Boolean;
    DryRun: Boolean;
    Style: TFormatStyle;
    InlineVar: Boolean;
  end;

  TMcpExtractTools = class
  public
    /// <summary>Plant bzw. schreibt die Extraktion; liefert Bericht und Diff. EMcpToolError, wenn die Zeilen
    /// keine vollständigen Anweisungen sind oder sich nicht extrahieren lassen (mit Grund).</summary>
    class function ExtractMethod(AEdit: TMcpEditTools; const ARequest: TMcpExtractRequest): string; static;
  end;

implementation

uses
  Atlas.Text.Lines,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.Extract,
  Atlas.Common.Mcp.Server,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen.</summary>
  TExtractToolsText = (IsNotReadable, BadLines, BadName, CannotExtract, Places, NoPlaces);

const
  cTexts: array[TExtractToolsText] of TAtlasText = (
    (De: '%s ist nicht lesbar'; En: '%s is not readable'),
    (De: '"startLine" ab 1 und "endLine" nicht davor, beide in der Datei';
     En: '"startLine" from 1 and "endLine" not before it, both within the file'),
    (De: '"%s" ist kein gültiger Bezeichner'; En: '"%s" is not a valid identifier'),
    (De: 'Methode extrahieren geht hier nicht: %s'; En: 'Extract method is not possible here: %s'),
    (De: 'Gleiche Stellen ersetzt (%d):'; En: 'Equal places replaced (%d):'),
    (De: 'Gleiche Stellen: %s'; En: 'Equal places: %s'));

{$SCOPEDENUMS OFF}

function ReadSource(AEdit: TMcpEditTools; const AFileName: string): string;
var
  mRead: TReferenceReadText;
begin
  mRead := AEdit.ReadText;
  if not mRead(AFileName, Result) then
  begin
    raise EMcpToolError.CreateFmt(cTexts[TExtractToolsText.IsNotReadable].Text, [AFileName]);
  end;
end;

/// <summary>Die ganzen Zeilen der Anfrage; EMcpToolError außerhalb der Datei.</summary>
function LinesRange(const AText: string; const ARequest: TMcpExtractRequest): TTextRange;
var
  mLines: TArray<string>;
begin
  mLines := TTextLines.SplitLines(AText);
  if (ARequest.StartLine < 1) or (ARequest.EndLine < ARequest.StartLine) or (ARequest.EndLine > Length(mLines)) then
  begin
    raise EMcpToolError.Create(cTexts[TExtractToolsText.BadLines].Text);
  end;
  Result := TTextRange.Create(ARequest.StartLine - 1, 0, ARequest.EndLine - 1, Length(mLines[ARequest.EndLine - 1]));
end;

function OptionsOf(const ARequest: TMcpExtractRequest): TExtractOptions;
begin
  Result := TExtractOptions.Default;
  Result.InlineVar := ARequest.InlineVar;
  Result.Style := ARequest.Style;
  Result.Duplicates := ARequest.ReplaceDuplicates;
  Result.MethodName := ARequest.Name;
end;

/// <summary>Aktion samt gleicher Stellen, wenn gewünscht und vorhanden; sonst nur die Auswahl. ANote nennt, warum
/// es keine gleichen Stellen gab.</summary>
function PlanAction(const AText: string; ATree: TSyntaxTree; const ARange: TTextRange;
  const AOptions: TExtractOptions; out ANote: string): TCodeAction;
var
  mReason: string;
begin
  ANote := '';
  if AOptions.Duplicates and TExtractRefactoring.ExtractMethodWithDuplicates(AText, ATree, ARange, AOptions, Result,
    mReason) then
  begin
    Exit;
  end;
  if AOptions.Duplicates then
  begin
    ANote := cTexts[TExtractToolsText.NoPlaces].Fmt([mReason]);
  end;
  if not TExtractRefactoring.ExtractMethod(AText, ATree, ARange, AOptions, Result, mReason) then
  begin
    raise EMcpToolError.CreateFmt(cTexts[TExtractToolsText.CannotExtract].Text, [mReason]);
  end;
end;

/// <summary>Kopfzeilen des Berichts: Titel und ersetzte Stellen.</summary>
function Summary(const AAction: TCodeAction; const ANote: string): string;
var
  mChoice: TCodeActionChoice;
begin
  Result := AAction.Title;
  if AAction.Choices <> nil then
  begin
    Result := Result + sLineBreak + cTexts[TExtractToolsText.Places].Fmt([Length(AAction.Choices)]);
    for mChoice in AAction.Choices do
    begin
      Result := Result + sLineBreak + '  ' + mChoice.Title;
    end;
  end;
  if ANote <> '' then
  begin
    Result := Result + sLineBreak + ANote;
  end;
end;

class function TMcpExtractTools.ExtractMethod(AEdit: TMcpEditTools; const ARequest: TMcpExtractRequest): string;
var
  mText, mNote: string;
  mTree: TSyntaxTree;
  mAction: TCodeAction;
  mEdit: TTextEdit;
  mEdits: TArray<TMcpFileEdit>;
begin
  if (ARequest.Name <> '') and not IsValidIdent(ARequest.Name) then
  begin
    raise EMcpToolError.CreateFmt(cTexts[TExtractToolsText.BadName].Text, [ARequest.Name]);
  end;
  mText := ReadSource(AEdit, ARequest.FileName);
  mTree := TPascalParser.Parse(mText);
  try
    mAction := PlanAction(mText, mTree, LinesRange(mText, ARequest), OptionsOf(ARequest), mNote);
  finally
    mTree.Free;
  end;
  // Ohne Auswahl im Client gelten alle Stellen.
  mEdits := nil;
  for mEdit in mAction.Edits do
  begin
    mEdits := mEdits + [TMcpFileEdit.Create(ARequest.FileName, mEdit.Range, mEdit.NewText)];
  end;
  Result := Summary(mAction, mNote) + sLineBreak + AEdit.Apply('extract_method', mEdits, ARequest.DryRun);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Mcp.ExtractTools', cTexts);

end.
