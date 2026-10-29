unit Atlas.Common.Mcp.EditTools;

// Schreibende MCP-Werkzeuge (#61) nach den Regeln aus #99:
//   rename_symbol      Symbol an Datei:Zeile:Spalte umbenennen, samt .dfm/.fmx
//                      und automatisch benannter Ereignis-Handler (#30)
//   apply_code_action  Korrektur eines Regeltreffers in einer Zeile anwenden
//   format_code        Datei oder geplanten Text nach den Formatregeln des
//                      Projekts formatieren (#1358), ganz oder einen Zeilenbereich
// dryRun (Vorgabe true) liefert nur den Diff und schreibt nichts. Mit
// dryRun=false wird atomar geschrieben: alle neuen Texte werden vorher
// berechnet; hat sich eine Datei seit dem Lesen geändert oder ist sie im Editor
// ungespeichert geändert (Liste des IDE-Plugins), bricht der Aufruf ohne
// Änderung ab; scheitert das Schreiben einer Datei, werden die schon
// geschriebenen zurückgesetzt. Geänderte Dateien gehen ins Protokoll (Audit).
// apply_code_action prüft mit den Symbolen des Projekts (CheckSource, #860) und
// mit Symbolindex und Projektdiensten (CheckProject, #1112) wie der Server.
// rename_symbol ändert nur sichere Stellen (#1119); erschlossene nennt der
// Bericht unter „Nicht geändert, bitte prüfen“.
// format_code schreibt über denselben Weg (offene Dateien über das Plugin als
// ein Rückgängig-Schritt, #397); mit Text statt Datei liefert es nur den
// formatierten Text. Dateien mit Syntaxfehlern formatiert es nicht. Die
// Zeilenenden der Datei bleiben dabei; format.endOfLine setzt --format-write um.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Checker,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.FormatCheck,
  Atlas.Common.Lsp.References;

type
  TMcpFileEdit = record
    FileName: string;
    Range: TTextRange;
    NewText: string;
    class function Create(const AFileName: string; const ARange: TTextRange; const ANewText: string): TMcpFileEdit; static;
  end;

  /// <summary>Schreibt AText nach AFileName (Kodierung und Zeilenenden erhalten); Fehler als Exception.</summary>
  TMcpWriteText = reference to procedure(const AFileName, AText: string);
  /// <summary>Im Editor ungespeichert geänderte Dateien (IDE-Plugin); leer ohne Editor.</summary>
  TMcpDirtyFiles = reference to function: TArray<string>;
  TMcpAudit = reference to procedure(const AText: string);

  TMcpEditTools = class
  private
    FIndex: ISymbolIndex;
    FReadText: TReferenceReadText;
    FWriteText: TMcpWriteText;
    FProjectFiles: TFunc<TArray<string>>;
    FEnsureUnit: TEnsureUnitFunc;
    FDirtyFiles: TMcpDirtyFiles;
    FAudit: TMcpAudit;
    FNamespaces: TArray<string>;
    FCheckSource: TCheckSourceFunc;
    FCheckProject: TCheckProjectFunc;
    FSettingsFor: TReferenceSettingsProvider;
  public
    constructor Create(const AIndex: ISymbolIndex; const AReadText: TReferenceReadText;
      const AWriteText: TMcpWriteText; const AProjectFiles: TFunc<TArray<string>>;
      const AEnsureUnit: TEnsureUnitFunc);
    /// <summary>Wendet Edits einer Datei auf AText an (von hinten nach vorn).</summary>
    class function ApplyToText(const AText: string; const AEdits: TArray<TMcpFileEdit>): string; static;
    /// <summary>Zeilen-Diff (- alt, + neu) mit Zeilennummern des alten Texts.</summary>
    class function Diff(const AFileName, AOld, ANew: string): string; static;
    /// <summary>Plant bzw. schreibt AEdits (siehe Unit-Kopf); liefert den Bericht.</summary>
    function Apply(const ATool: string; const AEdits: TArray<TMcpFileEdit>; ADryRun: Boolean): string;
    function RenameSymbol(const AFileName: string; ALine, AColumn: Integer; const ANewName: string;
      ADryRun: Boolean): string;
    /// <summary>Ohne ATitle: verfügbare Korrekturen der Zeile auflisten, nichts ändern.</summary>
    function ApplyCodeAction(const ARules: TArray<IRule>; const ASettings: TServerSettings;
      const ARoot, AFileName: string; ALine: Integer; const ATitle: string; ADryRun: Boolean): string;
    /// <summary>format_code mit Text (#1358): formatiert AText (geplanter Inhalt von AFileName) nach AStyle und
    /// liefert die Abweichungen und den formatierten Text; schreibt nichts.</summary>
    function FormatCode(const AStyle: TFormatStyle; const AFileName, AText: string;
      const AScope: TFormatScope): string; overload;
    /// <summary>format_code für die Datei (#1358): Vorschau als Diff bzw. mit ADryRun = False schreiben wie
    /// apply_code_action.</summary>
    function FormatCode(const AStyle: TFormatStyle; const AFileName: string; const AScope: TFormatScope;
      ADryRun: Boolean): string; overload;
    property Namespaces: TArray<string> read FNamespaces write FNamespaces;
    property DirtyFiles: TMcpDirtyFiles read FDirtyFiles write FDirtyFiles;
    property Audit: TMcpAudit read FAudit write FAudit;
    /// <summary>Symbole und Include-Dateien für die Regelprüfung (#860); nil = Vordefinitionen (Win32).</summary>
    property CheckSource: TCheckSourceFunc read FCheckSource write FCheckSource;
    /// <summary>Projekt, Symbolindex und Projektdienste für die Regelprüfung (#1112); nil = ohne Index.</summary>
    property CheckProject: TCheckProjectFunc read FCheckProject write FCheckProject;
    /// <summary>Einstellungen references.* (#1119); nicht gesetzt: Vorgaben.</summary>
    property SettingsFor: TReferenceSettingsProvider read FSettingsFor write FSettingsFor;
  end;

implementation

uses
  System.Classes,
  System.StrUtils,
  System.Math,
  System.Generics.Defaults,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Lsp.ReferenceConfidence,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Rules.CodeActions,
  Atlas.Common.Rules.Scopes,
  Atlas.Common.Lsp.Rename,
  Atlas.Common.Editing.TextChanges,
  Atlas.Common.Mcp.Server,
  Atlas.Text.Lines,
  Atlas.Text.Diff;

{ TMcpFileEdit }

class function TMcpFileEdit.Create(const AFileName: string; const ARange: TTextRange;
  const ANewText: string): TMcpFileEdit;
begin
  Result.FileName := AFileName;
  Result.Range := ARange;
  Result.NewText := ANewText;
end;

{ TMcpEditTools }

constructor TMcpEditTools.Create(const AIndex: ISymbolIndex; const AReadText: TReferenceReadText;
  const AWriteText: TMcpWriteText; const AProjectFiles: TFunc<TArray<string>>;
  const AEnsureUnit: TEnsureUnitFunc);
begin
  inherited Create;
  FIndex := AIndex;
  FReadText := AReadText;
  FWriteText := AWriteText;
  FProjectFiles := AProjectFiles;
  FEnsureUnit := AEnsureUnit;
end;

class function TMcpEditTools.ApplyToText(const AText: string; const AEdits: TArray<TMcpFileEdit>): string;
var
  Sorted: TArray<TMcpFileEdit>;
  Edit: TMcpFileEdit;
  StartOffset, EndOffset: Integer;
  Lines: TLineTable;
begin
  Sorted := Copy(AEdits);
  TArray.Sort<TMcpFileEdit>(Sorted, TComparer<TMcpFileEdit>.Construct(
    function(const A, B: TMcpFileEdit): Integer
    begin
      Result := B.Range.StartPos.Line - A.Range.StartPos.Line;
      if Result = 0 then
        Result := B.Range.StartPos.Character - A.Range.StartPos.Character;
    end));
  Result := AText;
  for Edit in Sorted do
  begin
    // Zeilen wie LSP (CRLF, LF, CR); Zeichen hinter dem Zeilenende zählen als Zeilenende.
    Lines := TLineTable.Build(Result);
    StartOffset := Lines.OffsetAt(Edit.Range.StartPos);
    EndOffset := Lines.OffsetAt(Edit.Range.EndPos);
    Result := Copy(Result, 1, StartOffset) + Edit.NewText + Copy(Result, EndOffset + 1, MaxInt);
  end;
end;

class function TMcpEditTools.Diff(const AFileName, AOld, ANew: string): string;
var
  Line: string;
  Builder: TStringBuilder;
begin
  Builder := TStringBuilder.Create;
  try
    Builder.AppendFormat('--- %s', [AFileName]).AppendLine;
    // Gleiche Zeilenzahl (z. B. Umbenennen): nur die geänderten Zeilen, sonst der geänderte Block.
    for Line in TTextDiff.ChangedLines(TTextLines.SplitLines(AOld), TTextLines.SplitLines(ANew)) do
      Builder.AppendLine(Line);
    Result := TrimRight(Builder.ToString);
  finally
    Builder.Free;
  end;
end;

function TMcpEditTools.Apply(const ATool: string; const AEdits: TArray<TMcpFileEdit>; ADryRun: Boolean): string;
var
  Files: TDictionary<string, TArray<TMcpFileEdit>>;
  Order: TList<string>;
  Edit: TMcpFileEdit;
  Key, FileName, Dirty, Current: string;
  OldTexts, NewTexts: TArray<string>;
  Names: TArray<string>;
  Index, Written: Integer;
  Report: TStringBuilder;
begin
  if Length(AEdits) = 0 then
    raise EMcpToolError.Create('Keine Änderungen.');
  Files := TDictionary<string, TArray<TMcpFileEdit>>.Create;
  Order := TList<string>.Create;
  Report := TStringBuilder.Create;
  try
    for Edit in AEdits do
    begin
      Key := AnsiLowerCase(Edit.FileName);
      if not Files.ContainsKey(Key) then
      begin
        Files.Add(Key, nil);
        Order.Add(Edit.FileName);
      end;
      Files[Key] := Files[Key] + [Edit];
    end;
    Names := Order.ToArray;
    SetLength(OldTexts, Length(Names));
    SetLength(NewTexts, Length(Names));
    for Index := 0 to High(Names) do
    begin
      if not FReadText(Names[Index], OldTexts[Index]) then
        raise EMcpToolError.CreateFmt('%s ist nicht lesbar; nichts geändert.', [Names[Index]]);
      NewTexts[Index] := ApplyToText(OldTexts[Index], Files[AnsiLowerCase(Names[Index])]);
    end;
    if ADryRun then
      Report.AppendFormat('Vorschau (dryRun): %d Änderungen in %d Dateien, nichts geschrieben. ' +
        'Zum Schreiben mit dryRun=false wiederholen.', [Length(AEdits), Length(Names)]).AppendLine
    else
    begin
      // Keine Kollision mit ungespeicherten Änderungen im Editor.
      if Assigned(FDirtyFiles) then
        for Dirty in FDirtyFiles() do
          for FileName in Names do
            if SameText(Dirty, FileName) then
              raise EMcpToolError.CreateFmt('%s hat ungespeicherte Änderungen im Editor; nichts geändert. ' +
                'Erst in der IDE speichern.', [FileName]);
      // Seit dem Lesen geändert? Dann nichts schreiben.
      for Index := 0 to High(Names) do
        if not FReadText(Names[Index], Current) or (Current <> OldTexts[Index]) then
          raise EMcpToolError.CreateFmt('%s wurde inzwischen geändert; nichts geändert.', [Names[Index]]);
      Written := 0;
      try
        for Index := 0 to High(Names) do
        begin
          FWriteText(Names[Index], NewTexts[Index]);
          Inc(Written);
        end;
      except
        on E: Exception do
        begin
          // Alles oder nichts: schon geschriebene Dateien zurücksetzen.
          for Index := Written - 1 downto 0 do
            try
              FWriteText(Names[Index], OldTexts[Index]);
            except
              on Exception do
                ;
            end;
          raise EMcpToolError.CreateFmt('Schreiben fehlgeschlagen (%s); alle Dateien zurückgesetzt.', [E.Message]);
        end;
      end;
      if Assigned(FAudit) then
        FAudit(Format('MCP %s hat geschrieben: %s', [ATool, string.Join(', ', Names)]));
      Report.AppendFormat('%d Änderungen in %d Dateien geschrieben.', [Length(AEdits), Length(Names)]).AppendLine;
    end;
    for Index := 0 to High(Names) do
    begin
      Report.AppendLine;
      Report.AppendLine(Diff(Names[Index], OldTexts[Index], NewTexts[Index]));
    end;
    Result := TrimRight(Report.ToString);
  finally
    Report.Free;
    Order.Free;
    Files.Free;
  end;
end;

function TMcpEditTools.RenameSymbol(const AFileName: string; ALine, AColumn: Integer; const ANewName: string;
  ADryRun: Boolean): string;
var
  Text: string;
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
  Renames: TArray<TRenameEdit>;
  Rename: TRenameEdit;
  Edits: TArray<TMcpFileEdit>;
  Settings: TReferenceSettings;
  Unchanged: TArray<TReferenceLocation>;
  Location: TReferenceLocation;
  Lines: TStringList;
begin
  if not FReadText(AFileName, Text) then
    raise EMcpToolError.CreateFmt('%s ist nicht lesbar', [AFileName]);
  if Assigned(FSettingsFor) then
    Settings := FSettingsFor(TDocumentUris.FromPath(AFileName))
  else
    Settings := TReferenceSettings.Default;
  Tree := TSyntaxTreeCache.Parse(Text);
  try
    Resolver := TNameResolver.Create(FIndex, FEnsureUnit);
    try
      Resolver.Namespaces := FNamespaces;
      try
        Renames := TLspRename.Edits(Resolver, FIndex, Tree, AFileName, TTextPosition.Create(ALine - 1, AColumn - 1),
          ANewName, FProjectFiles(), FReadText, nil, True, Settings, Unchanged);
      except
        on E: EJsonRpcError do
          raise EMcpToolError.Create(E.Message);
      end;
    finally
      Resolver.Free;
    end;
  finally
    Tree.Free;
  end;
  Edits := nil;
  for Rename in Renames do
    Edits := Edits + [TMcpFileEdit.Create(Rename.FileName, Rename.Range, Rename.NewText)];
  if Length(Edits) = 0 then
    raise EMcpToolError.Create('An dieser Stelle steht kein umbenennbares Symbol.');
  Result := Apply('rename_symbol', Edits, ADryRun);
  if Length(Unchanged) = 0 then
    Exit;
  Lines := TStringList.Create;
  try
    Lines.Add('');
    Lines.Add(Format('Nicht geändert, bitte prüfen (%d erschlossene Stellen):', [Length(Unchanged)]));
    for Location in Unchanged do
      Lines.Add(Format('%s:%d:%d – %s: %s', [Location.FileName, Location.Range.StartPos.Line + 1,
        Location.Range.StartPos.Character + 1, Location.Confidence.ReasonName, Location.Confidence.Detail]));
    Result := Result + sLineBreak + TrimRight(Lines.Text);
  finally
    Lines.Free;
  end;
end;

function TMcpEditTools.ApplyCodeAction(const ARules: TArray<IRule>; const ASettings: TServerSettings;
  const ARoot, AFileName: string; ALine: Integer; const ATitle: string; ADryRun: Boolean): string;
var
  Text, RelativePath: string;
  Actions: TArray<TCodeAction>;
  Action: TCodeAction;
  Chosen: Integer;
  Index: Integer;
  Edit: TRuleEdit;
  Edits: TArray<TMcpFileEdit>;
  Lines: TStringList;
  Scopes: TFindingScopes;
begin
  if not FReadText(AFileName, Text) then
    raise EMcpToolError.CreateFmt('%s ist nicht lesbar', [AFileName]);
  RelativePath := AFileName;
  if (ARoot <> '') and StartsText(IncludeTrailingPathDelimiter(ARoot), AFileName) then
    RelativePath := Copy(AFileName, Length(IncludeTrailingPathDelimiter(ARoot)) + 1, MaxInt);
  Actions := nil;
  for Action in TRuleCodeActions.ForRange(TFileChecker.CheckText(ARules, ASettings, RelativePath, Text,
    TFileChecker.ProjectOf(FCheckProject, AFileName), TFileChecker.SourceOf(FCheckSource, AFileName), Scopes), Text,
    TTextRange.Create(ALine - 1, 0, ALine - 1, MaxInt div 2)) do
    if (Length(Action.Edits) > 0) and (Action.Command = '') then
      Actions := Actions + [Action];
  if Length(Actions) = 0 then
    raise EMcpToolError.CreateFmt('Keine Korrektur in Zeile %d.', [ALine]);
  Chosen := -1;
  // Über die Regelkennung nur echte Korrekturen: Unterdrücken behebt nichts und braucht seinen Titel (#1109).
  if ATitle <> '' then
    for Index := 0 to High(Actions) do
      if SameText(Actions[Index].Title, ATitle) or (SameText(Actions[Index].RuleId, ATitle) and
        not MatchStr(Actions[Index].Tag, [RuleSuppressLineTag, RuleSuppressFileTag])) then
      begin
        Chosen := Index;
        Break;
      end;
  if Chosen < 0 then
  begin
    Lines := TStringList.Create;
    try
      if ATitle <> '' then
        Lines.Add(Format('Keine Korrektur "%s" in Zeile %d. Verfügbar:', [ATitle, ALine]))
      else
        Lines.Add(Format('Korrekturen in Zeile %d (mit title anwenden):', [ALine]));
      for Action in Actions do
        Lines.Add(Format('- %s [%s]', [Action.Title, Action.RuleId]));
      Result := TrimRight(Lines.Text);
    finally
      Lines.Free;
    end;
    if ATitle <> '' then
      raise EMcpToolError.Create(Result);
    Exit;
  end;
  Edits := nil;
  for Edit in Actions[Chosen].Edits do
    Edits := Edits + [TMcpFileEdit.Create(AFileName, Edit.Range, Edit.NewText)];
  Result := Format('Korrektur: %s', [Actions[Chosen].Title]) + sLineBreak + Apply('apply_code_action', Edits, ADryRun);
end;

/// <summary>Ergebnis von format_code ohne Syntaxfehler: Zahl und erste Abweichungen; '' ohne Abweichung.</summary>
function DeviationReport(const AFileName: string; const AOutcome: TFormatOutcome): string;
const
  cShown = 20;
var
  mLines: TStringList;
  mIndex: Integer;
begin
  mLines := TStringList.Create;
  try
    mLines.Add(Format('%s: %d Abweichungen von den Formatregeln', [ExtractFileName(AFileName),
      Length(AOutcome.Deviations)]));
    for mIndex := 0 to Min(Length(AOutcome.Deviations), cShown) - 1 do
      mLines.Add(Format('- Zeile %d: %s', [AOutcome.Deviations[mIndex].Line + 1,
        AOutcome.Deviations[mIndex].Message]));
    if Length(AOutcome.Deviations) > cShown then
      mLines.Add(Format('- … und %d weitere', [Length(AOutcome.Deviations) - cShown]));
    if not AOutcome.Stable then
      mLines.Add('Hinweis: Die Formatierung ist nicht stabil, ein zweiter Lauf ändert erneut.');
    Result := TrimRight(mLines.Text);
  finally
    mLines.Free;
  end;
end;

/// <summary>Formatiert AText; EMcpToolError bei Syntaxfehlern.</summary>
function FormatOrFail(const AStyle: TFormatStyle; const AFileName, AText: string; const AScope: TFormatScope;
  const ASource: TCheckSource): TFormatOutcome;
begin
  Result := TFormatCheck.Run(AText, AStyle, AScope, ASource.Options);
  if Result.HasSyntaxError then
    raise EMcpToolError.CreateFmt('%s: Syntaxfehler in Zeile %d, nicht formatiert: %s',
      [ExtractFileName(AFileName), Result.SyntaxError.StartPos.Line + 1, Result.SyntaxError.Message]);
end;

function TMcpEditTools.FormatCode(const AStyle: TFormatStyle; const AFileName, AText: string;
  const AScope: TFormatScope): string;
var
  mOutcome: TFormatOutcome;
begin
  mOutcome := FormatOrFail(AStyle, AFileName, AText, AScope, TFileChecker.SourceOf(FCheckSource, AFileName));
  if not mOutcome.Changed then
    Exit('Keine Abweichung von den Formatregeln; der Text bleibt, wie er ist.');
  Result := DeviationReport(AFileName, mOutcome) + sLineBreak + sLineBreak + 'Formatierter Text:' + sLineBreak +
    '```pascal' + sLineBreak + mOutcome.Formatted + sLineBreak + '```';
end;

function TMcpEditTools.FormatCode(const AStyle: TFormatStyle; const AFileName: string;
  const AScope: TFormatScope; ADryRun: Boolean): string;
var
  mText: string;
  mOutcome: TFormatOutcome;
  mEdit: TTextEdit;
  mEdits: TArray<TMcpFileEdit>;
begin
  if not FReadText(AFileName, mText) then
    raise EMcpToolError.CreateFmt('%s ist nicht lesbar', [AFileName]);
  mOutcome := FormatOrFail(AStyle, AFileName, mText, AScope, TFileChecker.SourceOf(FCheckSource, AFileName));
  if not mOutcome.Changed then
    Exit(Format('%s: keine Abweichung von den Formatregeln.', [ExtractFileName(AFileName)]));
  mEdits := nil;
  for mEdit in TTextChanges.Diff(mText, mOutcome.Formatted) do
    mEdits := mEdits + [TMcpFileEdit.Create(AFileName, mEdit.Range, mEdit.NewText)];
  // Die Datei behält ihre Zeilenenden (TFileEncoding beim Schreiben); andere setzt --format-write um.
  if Length(mEdits) = 0 then
    Exit(DeviationReport(AFileName, mOutcome) + sLineBreak + 'Nur die Zeilenenden weichen ab (format.endOfLine); ' +
      'format_code ändert sie nicht, dafür AtlasServer --check <Datei> --format-write verwenden.');
  Result := DeviationReport(AFileName, mOutcome) + sLineBreak + sLineBreak + Apply('format_code', mEdits, ADryRun);
end;

end.
