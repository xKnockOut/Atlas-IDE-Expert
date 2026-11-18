unit Atlas.Common.Mcp.CompilerMessageTools;

// MCP-Werkzeug explain_compiler_message (#2621): erklärt Compilermeldungen an ihrer Stelle für KI-Assistenten.
// Je Meldung die allgemeine Erklärung aus TCompilerMessageCatalog, die Fallen aus TCompilerPitfalls (zuerst die mit
// Merkmal an der Stelle), die Atlas-Regeln, die die Meldung schon beim Tippen bringen (Falle und "compilerCodes" des
// Regelkatalogs), und eine Korrektur: als vereinigter Diff, wenn sie sicher ist (TCompilerFixes, TCompilerPitfallFixes),
// sonst als Text. Mehrere Meldungen in einem Aufruf (messages, z. B. die Ausgabe von build_project); Folgefehler
// (E2250 nach E2003/E2010 in derselben Datei) sind markiert. Steht der Name aus der Meldung nicht mehr in ihrer
// Zeile, weil die Datei seit dem Build geändert wurde, sucht das Werkzeug ihn in der Nähe und sagt das.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Mcp.IndexTools;

type
  /// <summary>Eine Compilermeldung; Line und Column ab 1, 0 = ohne.</summary>
  TMcpCompilerMessage = record
    Code: string;
    Text: string;
    FileName: string;
    Line: Integer;
    Column: Integer;
  end;

  TMcpExplainRequest = record
    Messages: TArray<TMcpCompilerMessage>;
    /// <summary>BDS-Version für die DocWiki-Links; '' = neueste.</summary>
    DelphiVersion: string;
    Json: Boolean;
    /// <summary>Liest den Quelltext zu FileName einer Meldung; nil oder False = ohne Stelle.</summary>
    ReadText: TMcpReadText;
  end;

  TMcpCompilerMessageTools = class
  public
    /// <summary>Meldungen aus den Argumenten: messages (Array) oder code/message/file/line/column. EMcpToolError ohne
    /// Meldung.</summary>
    class function MessagesOf(const AArguments: TJSONObject): TArray<TMcpCompilerMessage>; static;
    /// <summary>Antwort des Werkzeugs als Markdown bzw. JSON.</summary>
    class function Explain(const ARequest: TMcpExplainRequest): string; static;
    /// <summary>Kennt Atlas zu ACode eine Erklärung (Katalog oder Falle)? Für den Hinweis in build_project.
    /// </summary>
    class function Explains(const ACode: string): Boolean; static;
  end;

implementation

uses
  System.StrUtils,
  // Inline-Funktionen von TJSONArray und TJSONObject (H2443).
  System.Generics.Collections,
  Atlas.Text.Lines,
  Atlas.Text.Chars,
  Atlas.Text.Json,
  Atlas.Text.Diff,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Editing.CompilerFixes,
  Atlas.Common.Editing.TextChanges,
  Atlas.Common.Rules.Catalog,
  Atlas.Common.Rules.CompilerPitfalls,
  Atlas.Common.Rules.CompilerPitfallFixes,
  Atlas.Common.Rules.MessageCatalog,
  Atlas.Common.Localization.Texts,
  Atlas.Common.Mcp.Server;

type
{$SCOPEDENUMS ON}
  TExplainText = (NoMessage, FollowUp, LineShifted, Likely, SafeFix, Fix, RulesWhileTyping, OtherCauses,
    Example, ExampleGood, DocWiki, Unknown);
{$SCOPEDENUMS OFF}

  /// <summary>Was das Werkzeug zu einer Meldung herausfindet.</summary>
  TExplanation = record
    Message: TMcpCompilerMessage;
    Known: Boolean;
    Entry: TCompilerMessageEntry;
    /// <summary>Nummer, von der die Meldung folgt; '' = keine.</summary>
    FollowUpOf: string;
    /// <summary>Zeile (ab 1), in der der Name aus der Meldung jetzt steht; 0 = unverändert.</summary>
    LineNow: Integer;
    Pitfalls: TArray<TPitfallMatch>;
    Rules: TArray<string>;
    FixTitle: string;
    /// <summary>Vereinigter Diff der sicheren Korrektur; '' = keine.</summary>
    Diff: string;
    DocWiki: string;
  end;

  /// <summary>Quelltext einer Meldung und Zeile ab 0 (-1 ohne).</summary>
  TMessageSource = record
    Text: string;
    Line: Integer;
  end;

const
  cSearchLines = 10;
  // Nummern, deren erster Name in Hochkommas in der Zeile der Meldung steht; nur dort sucht NearestLine.
  cNamesOnLine: array[0..5] of string = ('E2003', 'E2250', 'W1000', 'W1036', 'H2077', 'H2164');
  cDiffContext = 3;
  cHeading = '## %s – %s';

  cTexts: array[TExplainText] of TAtlasText = (
    (De: 'Keine Meldung: code, message oder messages angeben.'; En: 'No message: give code, message or messages.'),
    (De: 'Folgefehler von %s weiter oben; zuerst jene Meldung beheben.';
     En: 'Follow-up error of %s further up; fix that message first.'),
    (De: 'Die Datei hat sich seit dem Build geändert: Die Stelle steht jetzt in Zeile %d.';
     En: 'The file has changed since the build: the place is now in line %d.'),
    (De: 'Wahrscheinlich: %s (%s). %s'; En: 'Likely: %s (%s). %s'),
    (De: 'Korrektur (sicher): %s'; En: 'Fix (safe): %s'),
    (De: 'Korrektur: %s'; En: 'Fix: %s'),
    (De: 'Regel beim Tippen: %s'; En: 'Rule while typing: %s'),
    (De: 'Weitere Ursachen: %s'; En: 'Other causes: %s'),
    (De: 'Beispiel falsch:'; En: 'Example wrong:'),
    (De: 'Richtig:'; En: 'Right:'),
    (De: 'DocWiki: %s'; En: 'DocWiki: %s'),
    (De: 'Zu %s kennt Atlas keine Erklärung; die Beschreibung steht im DocWiki.';
     En: 'Atlas knows no explanation for %s; the DocWiki has the description.'));

{ Argumente }

function MessageOf(AObject: TJSONObject): TMcpCompilerMessage;
begin
  Result := Default(TMcpCompilerMessage);
  Result.Text := AObject.GetValue<string>('message', AObject.GetValue<string>('text', ''));
  Result.Code := UpperCase(Trim(AObject.GetValue<string>('code', '')));
  if Result.Code = '' then
  begin
    Result.Code := TCompilerMessageCatalog.CodeOf(Result.Text);
  end;
  Result.FileName := AObject.GetValue<string>('file', '');
  Result.Line := AObject.GetValue<Integer>('line', 0);
  Result.Column := AObject.GetValue<Integer>('column', 0);
end;

{ Stelle }

function IsIdentifier(const AName: string): Boolean;
var
  mChar: Char;
begin
  Result := AName <> '';
  for mChar in AName do
  begin
    Result := Result and TTextChars.IsAsciiIdentChar(mChar);
  end;
end;

/// <summary>Erster Bezeichner in Hochkommas der Meldung; '' ohne.</summary>
function NameOf(const AText: string): string;
var
  mName: string;
begin
  for mName in TCompilerFixes.QuotedNames(AText) do
  begin
    if IsIdentifier(mName) then
    begin
      Exit(mName);
    end;
  end;
  Result := '';
end;

/// <summary>Zeile (ab 0) nahe ALine, in der AName steht; ALine, wenn er dort steht oder nirgends in der Nähe.
/// </summary>
function NearestLine(const ALines: TArray<string>; ALine: Integer; const AName: string): Integer;
var
  mDistance: Integer;
begin
  Result := ALine;
  if (AName = '') or ContainsText(TTextLines.LineAt(ALines, ALine), AName) then
  begin
    Exit;
  end;
  for mDistance := 1 to cSearchLines do
  begin
    if ContainsText(TTextLines.LineAt(ALines, ALine - mDistance), AName) then
    begin
      Exit(ALine - mDistance);
    end;
    if ContainsText(TTextLines.LineAt(ALines, ALine + mDistance), AName) then
    begin
      Exit(ALine + mDistance);
    end;
  end;
end;

function SourceOf(const ARequest: TMcpExplainRequest; const AMessage: TMcpCompilerMessage;
  var AExplanation: TExplanation): TMessageSource;
var
  mLines: TArray<string>;
begin
  Result.Text := '';
  Result.Line := -1;
  if (AMessage.FileName = '') or (AMessage.Line <= 0) or not Assigned(ARequest.ReadText) or
    not ARequest.ReadText(AMessage.FileName, Result.Text) then
  begin
    Result.Text := '';
    Exit;
  end;
  mLines := TTextLines.SplitLines(Result.Text);
  Result.Line := AMessage.Line - 1;
  if IndexText(AMessage.Code, cNamesOnLine) >= 0 then
  begin
    Result.Line := NearestLine(mLines, Result.Line, NameOf(AMessage.Text));
  end;
  if Result.Line <> AMessage.Line - 1 then
  begin
    AExplanation.LineNow := Result.Line + 1;
  end;
end;

{ Regeln und Korrekturen }

procedure AddRule(var ARules: TArray<string>; const ARule: string);
begin
  if (ARule <> '') and (IndexText(ARule, ARules) < 0) then
  begin
    ARules := ARules + [ARule];
  end;
end;

/// <summary>Regeln der Fallen mit Merkmal, dann die Regeln mit ACode in "compilerCodes".</summary>
function RulesOf(const ACode: string; const APitfalls: TArray<TPitfallMatch>): TArray<string>;
var
  mMatch: TPitfallMatch;
  mEntry: TRuleCatalogEntry;
begin
  Result := nil;
  for mMatch in APitfalls do
  begin
    if mMatch.Marked then
    begin
      AddRule(Result, TCompilerPitfalls.Info(mMatch.Pitfall, TAtlasLocale.Language).Rule);
    end;
  end;
  for mEntry in TRuleCatalog.Shared.Entries do
  begin
    if IndexText(ACode, mEntry.CompilerCodes) >= 0 then
    begin
      AddRule(Result, mEntry.Id);
    end;
  end;
end;

/// <summary>Vereinigter Diff für AEdits in ASource.Text; '' ohne Änderung.</summary>
function DiffOf(const AFileName, AText: string; const AEdits: TArray<TTextEdit>): string;
var
  mName: string;
begin
  mName := AFileName.Replace('\', '/');
  Result := string.Join(#10, TTextDiff.Unified('a/' + mName, 'b/' + mName, TTextLines.SplitLines(AText),
    TTextLines.SplitLines(TTextChanges.Apply(AText, AEdits)), cDiffContext));
end;

/// <summary>Bevorzugte Korrektur aus TCompilerFixes; False ohne.</summary>
function CompilerFixOf(const AMessage: TMcpCompilerMessage; const ASource: TMessageSource; ATree: TSyntaxTree;
  out AFix: TCompilerFix): Boolean;
var
  mFix: TCompilerFix;
  mFixes: TArray<TCompilerFix>;
begin
  AFix := Default(TCompilerFix);
  mFixes := TCompilerFixes.Fixes(ASource.Text, ATree, TFixMessage.Create(AMessage.Code, ASource.Line,
    AMessage.Column - 1, AMessage.Text), Default(TCompilerFixContext));
  for mFix in mFixes do
  begin
    if mFix.Preferred or (AFix.Edits = nil) then
    begin
      AFix := mFix;
    end;
  end;
  Result := AFix.Edits <> nil;
end;

/// <summary>Sichere Korrektur der ersten Falle mit Merkmal, die eine hat; False ohne.</summary>
function PitfallFixOf(const AExplanation: TExplanation; const ASource: TMessageSource; ATree: TSyntaxTree;
  out ATitle: string; out AEdits: TArray<TTextEdit>): Boolean;
var
  mMatch: TPitfallMatch;
begin
  ATitle := '';
  AEdits := nil;
  for mMatch in AExplanation.Pitfalls do
  begin
    if mMatch.Marked and TCompilerPitfallFixes.Edits(mMatch.Pitfall, ASource.Text, ATree, ASource.Line, AEdits) then
    begin
      ATitle := TCompilerPitfalls.Info(mMatch.Pitfall, TAtlasLocale.Language).Fix;
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure AddSafeFix(var AExplanation: TExplanation; const ASource: TMessageSource);
var
  mTree: TSyntaxTree;
  mFix: TCompilerFix;
  mEdits: TArray<TTextEdit>;
begin
  mTree := TSyntaxTreeCache.Parse(ASource.Text);
  try
    if CompilerFixOf(AExplanation.Message, ASource, mTree, mFix) then
    begin
      AExplanation.FixTitle := mFix.Title;
      mEdits := mFix.Edits;
    end
    else if not PitfallFixOf(AExplanation, ASource, mTree, AExplanation.FixTitle, mEdits) then
    begin
      Exit;
    end;
  finally
    mTree.Free;
  end;
  AExplanation.Diff := DiffOf(AExplanation.Message.FileName, ASource.Text, mEdits);
end;

{ Erklärung }

function Previous(const AMessages: TArray<TMcpCompilerMessage>; AIndex: Integer): TArray<string>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to AIndex - 1 do
  begin
    if SameText(AMessages[mIndex].FileName, AMessages[AIndex].FileName) then
    begin
      Result := Result + [AMessages[mIndex].Code];
    end;
  end;
end;

function ExplanationOf(const ARequest: TMcpExplainRequest; AIndex: Integer): TExplanation;
var
  mSource: TMessageSource;
begin
  Result := Default(TExplanation);
  Result.Message := ARequest.Messages[AIndex];
  Result.Known := TCompilerMessageCatalog.TryFind(Result.Message.Code, TAtlasLocale.Language, Result.Entry);
  TCompilerPitfalls.IsFollowUp(Result.Message.Code, Previous(ARequest.Messages, AIndex), Result.FollowUpOf);
  mSource := SourceOf(ARequest, Result.Message, Result);
  Result.Pitfalls := TCompilerPitfalls.Match(TPitfallMessage.Create(Result.Message.Code, Result.Message.Text,
    mSource.Line), mSource.Text);
  Result.Rules := RulesOf(Result.Message.Code, Result.Pitfalls);
  Result.DocWiki := TCompilerMessageCatalog.DocWikiUrl(Result.Message.Code, ARequest.DelphiVersion);
  if mSource.Line >= 0 then
  begin
    AddSafeFix(Result, mSource);
  end;
end;

{ Markdown }

function Location(const AMessage: TMcpCompilerMessage): string;
begin
  Result := '';
  if AMessage.FileName <> '' then
  begin
    Result := ' (' + ExtractFileName(AMessage.FileName.Replace('\', PathDelim).Replace('/', PathDelim));
    if AMessage.Line > 0 then
    begin
      Result := Result + ':' + IntToStr(AMessage.Line);
    end;
    Result := Result + ')';
  end;
end;

function MessageName(const AExplanation: TExplanation): string;
begin
  Result := AExplanation.Message.Text;
  if AExplanation.Known then
  begin
    Result := AExplanation.Entry.Name;
  end;
end;

procedure AddPitfallLines(ALines: TStringBuilder; const AExplanation: TExplanation);
var
  mMatch: TPitfallMatch;
  mInfo: TCompilerPitfallInfo;
  mOthers: TArray<string>;
  mFirst: Boolean;
begin
  mOthers := nil;
  mFirst := True;
  for mMatch in AExplanation.Pitfalls do
  begin
    mInfo := TCompilerPitfalls.Info(mMatch.Pitfall, TAtlasLocale.Language);
    if mMatch.Marked and mFirst then
    begin
      ALines.AppendLine(cTexts[TExplainText.Likely].Fmt([mInfo.Title, mMatch.Evidence, mInfo.Reason]));
      if AExplanation.Diff = '' then
      begin
        ALines.AppendLine(cTexts[TExplainText.Fix].Fmt([mInfo.Fix]));
      end;
      mFirst := False;
    end
    else
    begin
      mOthers := mOthers + [mInfo.Title];
    end;
  end;
  if AExplanation.Known then
  begin
    mOthers := mOthers + [AExplanation.Entry.Cause];
  end;
  if mOthers <> nil then
  begin
    ALines.AppendLine(cTexts[TExplainText.OtherCauses].Fmt([string.Join('; ', mOthers)]));
  end;
end;

procedure AddFixLines(ALines: TStringBuilder; const AExplanation: TExplanation);
begin
  if AExplanation.Diff <> '' then
  begin
    ALines.AppendLine(cTexts[TExplainText.SafeFix].Fmt([AExplanation.FixTitle]));
    ALines.AppendLine('```diff');
    ALines.AppendLine(AExplanation.Diff);
    ALines.AppendLine('```');
  end;
end;

function HasMarked(const AExplanation: TExplanation): Boolean;
var
  mMatch: TPitfallMatch;
begin
  for mMatch in AExplanation.Pitfalls do
  begin
    if mMatch.Marked then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure AddExample(ALines: TStringBuilder; const AExplanation: TExplanation);
begin
  if AExplanation.Known and not HasMarked(AExplanation) then
  begin
    ALines.AppendLine(cTexts[TExplainText.Example].Text);
    ALines.AppendLine('```pascal');
    ALines.AppendLine(AExplanation.Entry.Bad);
    ALines.AppendLine('```');
    ALines.AppendLine(cTexts[TExplainText.ExampleGood].Text);
    ALines.AppendLine('```pascal');
    ALines.AppendLine(AExplanation.Entry.Good);
    ALines.AppendLine('```');
  end;
end;

procedure AddMarkdown(ALines: TStringBuilder; const AExplanation: TExplanation);
begin
  ALines.AppendLine(Format(cHeading, [AExplanation.Message.Code, MessageName(AExplanation)]) +
    Location(AExplanation.Message));
  if AExplanation.Known then
  begin
    ALines.AppendLine(AExplanation.Entry.Description);
  end
  else if AExplanation.Pitfalls = nil then
  begin
    ALines.AppendLine(cTexts[TExplainText.Unknown].Fmt([AExplanation.Message.Code]));
  end;
  if AExplanation.FollowUpOf <> '' then
  begin
    ALines.AppendLine(cTexts[TExplainText.FollowUp].Fmt([AExplanation.FollowUpOf]));
  end;
  if AExplanation.LineNow > 0 then
  begin
    ALines.AppendLine(cTexts[TExplainText.LineShifted].Fmt([AExplanation.LineNow]));
  end;
  AddFixLines(ALines, AExplanation);
  AddPitfallLines(ALines, AExplanation);
  if AExplanation.Rules <> nil then
  begin
    ALines.AppendLine(cTexts[TExplainText.RulesWhileTyping].Fmt([string.Join(', ', AExplanation.Rules)]));
  end;
  AddExample(ALines, AExplanation);
  ALines.AppendLine(cTexts[TExplainText.DocWiki].Fmt([AExplanation.DocWiki]));
end;

{ JSON }

function PitfallJson(const AMatch: TPitfallMatch): TJSONObject;
var
  mInfo: TCompilerPitfallInfo;
begin
  mInfo := TCompilerPitfalls.Info(AMatch.Pitfall, TAtlasLocale.Language);
  Result := TJSONObject.Create;
  Result.AddPair('id', mInfo.Id);
  Result.AddPair('title', mInfo.Title);
  Result.AddPair('marked', TJSONBool.Create(AMatch.Marked));
  if AMatch.Marked then
  begin
    Result.AddPair('evidence', AMatch.Evidence);
  end;
  Result.AddPair('reason', mInfo.Reason);
  Result.AddPair('fix', mInfo.Fix);
  if mInfo.Rule <> '' then
  begin
    Result.AddPair('rule', mInfo.Rule);
  end;
end;

procedure AddCatalogJson(AItem: TJSONObject; const AExplanation: TExplanation);
begin
  AItem.AddPair('known', TJSONBool.Create(AExplanation.Known));
  if AExplanation.Known then
  begin
    AItem.AddPair('name', AExplanation.Entry.Name);
    AItem.AddPair('description', AExplanation.Entry.Description);
    AItem.AddPair('cause', AExplanation.Entry.Cause);
    AItem.AddPair('bad', AExplanation.Entry.Bad);
    AItem.AddPair('good', AExplanation.Entry.Good);
  end;
end;

function FixJson(const AExplanation: TExplanation): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('title', AExplanation.FixTitle);
  Result.AddPair('safe', TJSONBool.Create(True));
  Result.AddPair('diff', AExplanation.Diff);
end;

function ExplanationJson(const AExplanation: TExplanation): TJSONObject;
var
  mPitfalls: TJSONArray;
  mMatch: TPitfallMatch;
begin
  Result := TJSONObject.Create;
  Result.AddPair('code', AExplanation.Message.Code);
  Result.AddPair('file', AExplanation.Message.FileName);
  Result.AddPair('line', TJSONNumber.Create(AExplanation.Message.Line));
  AddCatalogJson(Result, AExplanation);
  if AExplanation.FollowUpOf <> '' then
  begin
    Result.AddPair('followUpOf', AExplanation.FollowUpOf);
  end;
  if AExplanation.LineNow > 0 then
  begin
    Result.AddPair('lineNow', TJSONNumber.Create(AExplanation.LineNow));
  end;
  mPitfalls := TJSONArray.Create;
  Result.AddPair('pitfalls', mPitfalls);
  for mMatch in AExplanation.Pitfalls do
  begin
    mPitfalls.AddElement(PitfallJson(mMatch));
  end;
  Result.AddPair('rules', TJsonBuild.Strings(AExplanation.Rules));
  if AExplanation.Diff <> '' then
  begin
    Result.AddPair('fix', FixJson(AExplanation));
  end;
  Result.AddPair('docWiki', AExplanation.DocWiki);
end;

{ TMcpCompilerMessageTools }

class function TMcpCompilerMessageTools.MessagesOf(const AArguments: TJSONObject): TArray<TMcpCompilerMessage>;
var
  mItems: TJSONArray;
  mItem: TJSONValue;
  mMessage: TMcpCompilerMessage;
begin
  Result := nil;
  if (AArguments <> nil) and AArguments.TryGetValue<TJSONArray>('messages', mItems) then
  begin
    for mItem in mItems do
    begin
      if mItem is TJSONObject then
      begin
        Result := Result + [MessageOf(TJSONObject(mItem))];
      end;
    end;
  end
  else if AArguments <> nil then
  begin
    mMessage := MessageOf(AArguments);
    if mMessage.Code <> '' then
    begin
      Result := [mMessage];
    end;
  end;
  if Result = nil then
  begin
    raise EMcpToolError.Create(cTexts[TExplainText.NoMessage].Text);
  end;
end;

class function TMcpCompilerMessageTools.Explain(const ARequest: TMcpExplainRequest): string;
var
  mIndex: Integer;
  mLines: TStringBuilder;
  mRoot: TJSONObject;
  mItems: TJSONArray;
begin
  if ARequest.Json then
  begin
    mRoot := TJSONObject.Create;
    try
      mItems := TJSONArray.Create;
      mRoot.AddPair('messages', mItems);
      for mIndex := 0 to High(ARequest.Messages) do
      begin
        mItems.AddElement(ExplanationJson(ExplanationOf(ARequest, mIndex)));
      end;
      Exit(mRoot.Format(2));
    finally
      mRoot.Free;
    end;
  end;
  mLines := TStringBuilder.Create;
  try
    for mIndex := 0 to High(ARequest.Messages) do
    begin
      if mIndex > 0 then
      begin
        mLines.AppendLine;
      end;
      AddMarkdown(mLines, ExplanationOf(ARequest, mIndex));
    end;
    Result := TrimRight(mLines.ToString);
  finally
    mLines.Free;
  end;
end;

class function TMcpCompilerMessageTools.Explains(const ACode: string): Boolean;
var
  mEntry: TCompilerMessageEntry;
begin
  Result := (ACode <> '') and (TCompilerMessageCatalog.TryFind(ACode, TTextLanguage.English, mEntry) or
    TCompilerPitfalls.Knows(ACode));
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Mcp.CompilerMessageTools', cTexts);

end.
