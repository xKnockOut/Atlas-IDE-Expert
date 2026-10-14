unit Atlas.Common.Mcp.CodeTools;

// MCP-Werkzeuge, die Quelltext auswerten (#48): Verwendungen, Aufrufhierarchie
// und Befunde der Prüfregeln. Das Symbol wird per Name über den Index gefunden
// und dann wie im LSP an seiner Deklaration aufgelöst.

interface

uses
  System.SysUtils,
  Atlas.Common.Index.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.References;

{$SCOPEDENUMS ON}

type
  TMcpCallDirection = (Incoming, Outgoing, Both);

  TMcpCodeTools = class
  public const
    MaxReferences = 200;
    MaxFindings = 200;
  private
    FIndex: ISymbolIndex;
    FReadText: TReferenceReadText;
    FFiles: TReferenceFilesProvider;
    FEnsureUnit: TEnsureUnitFunc;
    FNamespaces: TArray<string>;
    function Locate(const AName: string; out ALocation: TSymbolLocation; out AHint: string): Boolean;
    function LineText(const AFileName: string; ALine: Integer): string;
  public
    constructor Create(const AIndex: ISymbolIndex; const AReadText: TReferenceReadText;
      const AFiles: TReferenceFilesProvider; const AEnsureUnit: TEnsureUnitFunc = nil);
    /// <summary>Alle Verwendungen des Symbols im Projekt, mit Zeile und Quelltext.</summary>
    function References(const AName: string): string;
    /// <summary>Aufrufer und/oder aufgerufene Routinen einer Methode oder Routine.</summary>
    function CallHierarchy(const AName: string; ADirection: TMcpCallDirection): string;
    /// <summary>qualified_name (#128): voll qualifizierter Name des Symbols an ALine/AColumn (ab 1);
    /// EMcpToolError, wenn dort keins steht.</summary>
    function QualifiedName(const AFileName: string; ALine, AColumn: Integer; AWithParameters: Boolean): string;
    /// <summary>Befunde der Prüfregeln und Syntaxfehler je Datei; ARoot für relative Pfade.</summary>
    class function Diagnostics(const ARules: TArray<IRule>; const ASettings: TServerSettings;
      const ARoot: string; const AFiles: TArray<string>; const AReadText: TReferenceReadText): string; static;
    class function ParseDirection(const AText: string): TMcpCallDirection; static;
    /// <summary>
    /// check_code (#178): prüft AText als neuen Inhalt von AFileName, ohne zu schreiben.
    /// Mit AStartLine > 0 ersetzt AText nur die Zeilen AStartLine..AEndLine (ab 1, einschließlich;
    /// AEndLine = AStartLine - 1 fügt vor AStartLine ein). Liefert Syntaxfehler, Regeltreffer und
    /// nicht auflösbare Bezeichner; Positionen beziehen sich auf den neuen Text.
    /// </summary>
    function CheckCode(const ARules: TArray<IRule>; const ASettings: TServerSettings; const ARoot, AFileName,
      AText: string; AStartLine, AEndLine: Integer): string;
    /// <summary>Ersetzt die Zeilen AStartLine..AEndLine (ab 1) von AOriginal durch AText; EMcpToolError bei
    /// ungültigem Bereich.</summary>
    class function ReplaceLines(const AOriginal, AText: string; AStartLine, AEndLine: Integer): string; static;
    property Namespaces: TArray<string> read FNamespaces write FNamespaces;
  end;

implementation

uses
  System.Classes,
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Lsp.Hierarchies,
  Atlas.Common.Lsp.QualifiedNames,
  Atlas.Common.Rules.Checker,
  Atlas.Common.Rules.Output,
  Atlas.Common.Mcp.IndexTools,
  Atlas.Common.Mcp.Server,
  Atlas.Common.Semantics.UnresolvedNames;

{ TMcpCodeTools }

constructor TMcpCodeTools.Create(const AIndex: ISymbolIndex; const AReadText: TReferenceReadText;
  const AFiles: TReferenceFilesProvider; const AEnsureUnit: TEnsureUnitFunc);
begin
  inherited Create;
  FIndex := AIndex;
  FReadText := AReadText;
  FFiles := AFiles;
  FEnsureUnit := AEnsureUnit;
end;

function TMcpCodeTools.Locate(const AName: string; out ALocation: TSymbolLocation; out AHint: string): Boolean;
var
  Lookup: TMcpIndexTools;
  Found: TArray<TSymbolLocation>;
begin
  AHint := '';
  Lookup := TMcpIndexTools.Create(FIndex, nil);
  try
    Found := Lookup.Matches(AName);
  finally
    Lookup.Free;
  end;
  Result := Length(Found) > 0;
  if Result then
  begin
    ALocation := Found[0];
    if Length(Found) > 1 then
      AHint := Format('Hinweis: %d Symbole dieses Namens, ausgewertet wird %s in %s. ' +
        'Mit TTyp.Name genauer fassen.', [Length(Found), ALocation.Symbol.QualifiedName, ALocation.UnitName]);
  end;
end;

function TMcpCodeTools.LineText(const AFileName: string; ALine: Integer): string;
var
  Text: string;
  Lines: TStringList;
begin
  Result := '';
  if not FReadText(AFileName, Text) then
    Exit;
  Lines := TStringList.Create;
  try
    Lines.Text := Text;
    if (ALine >= 0) and (ALine < Lines.Count) then
      Result := Trim(Lines[ALine]);
  finally
    Lines.Free;
  end;
end;

function TMcpCodeTools.QualifiedName(const AFileName: string; ALine, AColumn: Integer;
  AWithParameters: Boolean): string;
var
  Text, Error: string;
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
begin
  if (ALine < 1) or (AColumn < 1) then
    raise EMcpToolError.Create('line und column zählen ab 1');
  if not FReadText(AFileName, Text) then
    raise EMcpToolError.CreateFmt('Datei %s nicht lesbar', [AFileName]);
  Tree := TSyntaxTreeCache.Parse(Text);
  try
    Resolver := TNameResolver.Create(FIndex, FEnsureUnit);
    try
      Resolver.Namespaces := FNamespaces;
      if not TQualifiedNames.At(Resolver, FIndex, Tree, AFileName, TTextPosition.Create(ALine - 1, AColumn - 1),
        AWithParameters, Result, Error) then
        raise EMcpToolError.Create(Error);
    finally
      Resolver.Free;
    end;
  finally
    Tree.Free;
  end;
end;

function TMcpCodeTools.References(const AName: string): string;
var
  Location: TSymbolLocation;
  Hint, Text: string;
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
  Files: TArray<string>;
  Found: TArray<TReferenceLocation>;
  Reference: TReferenceLocation;
  Lines: TStringList;
  Count: Integer;
begin
  if not Locate(AName, Location, Hint) then
    Exit(Format('Kein Symbol "%s" im Index.', [AName]));
  if not FReadText(Location.FileName, Text) then
    Exit(Format('Datei %s nicht lesbar.', [Location.FileName]));
  Files := nil;
  if Assigned(FFiles) then
    Files := FFiles();
  Tree := TSyntaxTreeCache.Parse(Text);
  try
    Resolver := TNameResolver.Create(FIndex, FEnsureUnit);
    try
      Resolver.Namespaces := FNamespaces;
      Found := TLspReferences.Find(Resolver, FIndex, Tree, Location.FileName,
        Location.Symbol.SelectionRange.StartPos, False, Files, FReadText);
    finally
      Resolver.Free;
    end;
  finally
    Tree.Free;
  end;
  Lines := TStringList.Create;
  try
    Lines.Add(Format('%d Verwendungen von %s (%s:%d):', [Length(Found), Location.Symbol.QualifiedName,
      Location.FileName, Location.Symbol.SelectionRange.StartPos.Line + 1]));
    Count := 0;
    for Reference in Found do
    begin
      if Count >= MaxReferences then
      begin
        Lines.Add(Format('… %d weitere', [Length(Found) - Count]));
        Break;
      end;
      Inc(Count);
      Lines.Add(Format('%s:%d: %s', [Reference.FileName, Reference.Range.StartPos.Line + 1,
        LineText(Reference.FileName, Reference.Range.StartPos.Line)]));
    end;
    if Hint <> '' then
      Lines.Add(Hint);
    Result := TrimRight(Lines.Text);
  finally
    Lines.Free;
  end;
end;

function DescribeItem(const AItem: THierarchyItem): string;
begin
  Result := AItem.Name;
  if AItem.Container <> '' then
    Result := AItem.Container + '.' + Result;
  Result := Format('%s – Unit %s, %s:%d', [Result, AItem.UnitName, AItem.FileName,
    AItem.SelectionRange.StartPos.Line + 1]);
end;

procedure AddCalls(ALines: TStrings; const ATitle, AArrow: string; const ACalls: TArray<THierarchyCall>);
var
  Call: THierarchyCall;
begin
  ALines.Add(ATitle);
  if Length(ACalls) = 0 then
    ALines.Add('  (keine)');
  for Call in ACalls do
    ALines.Add(Format('  %s %s (%d×)', [AArrow, DescribeItem(Call.Item), Length(Call.Ranges)]));
end;

function TMcpCodeTools.CallHierarchy(const AName: string; ADirection: TMcpCallDirection): string;
var
  Location: TSymbolLocation;
  Hint, Text: string;
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
  Item: THierarchyItem;
  Files: TArray<string>;
  Lines: TStringList;
begin
  if not Locate(AName, Location, Hint) then
    Exit(Format('Kein Symbol "%s" im Index.', [AName]));
  if not FReadText(Location.FileName, Text) then
    Exit(Format('Datei %s nicht lesbar.', [Location.FileName]));
  Files := nil;
  if Assigned(FFiles) then
    Files := FFiles();
  Lines := TStringList.Create;
  try
    Tree := TSyntaxTreeCache.Parse(Text);
    try
      Resolver := TNameResolver.Create(FIndex, FEnsureUnit);
      try
        Resolver.Namespaces := FNamespaces;
        if not TLspHierarchies.CallItemAt(Resolver, Tree, Location.FileName,
          Location.Symbol.SelectionRange.StartPos, Item) then
          Exit(Format('%s ist keine Routine oder Methode.', [Location.Symbol.QualifiedName]));
        Lines.Add(DescribeItem(Item));
        if ADirection in [TMcpCallDirection.Incoming, TMcpCallDirection.Both] then
          AddCalls(Lines, 'Aufgerufen von:', '←',
            TLspHierarchies.IncomingCalls(Resolver, FIndex, Item, Files, FReadText));
        if ADirection in [TMcpCallDirection.Outgoing, TMcpCallDirection.Both] then
          AddCalls(Lines, 'Ruft auf:', '→', TLspHierarchies.OutgoingCalls(Resolver, Item, FReadText));
      finally
        Resolver.Free;
      end;
    finally
      Tree.Free;
    end;
    if Hint <> '' then
      Lines.Add(Hint);
    Result := TrimRight(Lines.Text);
  finally
    Lines.Free;
  end;
end;

class function TMcpCodeTools.Diagnostics(const ARules: TArray<IRule>; const ASettings: TServerSettings;
  const ARoot: string; const AFiles: TArray<string>; const AReadText: TReferenceReadText): string;
var
  Lines: TStringList;
  FileName, RelativePath, Text: string;
  Finding: TRuleFinding;
  Count, Checked: Integer;
begin
  Lines := TStringList.Create;
  try
    Count := 0;
    Checked := 0;
    for FileName in AFiles do
    begin
      if not AReadText(FileName, Text) then
      begin
        Lines.Add(Format('%s: nicht lesbar', [FileName]));
        Continue;
      end;
      Inc(Checked);
      RelativePath := FileName;
      if (ARoot <> '') and StartsText(IncludeTrailingPathDelimiter(ARoot), FileName) then
        RelativePath := Copy(FileName, Length(IncludeTrailingPathDelimiter(ARoot)) + 1, MaxInt);
      for Finding in TFileChecker.CheckText(ARules, ASettings, RelativePath, Text) do
      begin
        Inc(Count);
        if Count <= MaxFindings then
          Lines.Add(Format('%s:%d:%d: %s [%s] [Konfidenz %s] %s', [FileName, Finding.Range.StartPos.Line + 1,
            Finding.Range.StartPos.Character + 1, TFindingsOutput.SeverityName(Finding.Severity),
            Finding.RuleId, ConfidenceText(Finding.Confidence), Finding.Message]));
      end;
    end;
    if Count > MaxFindings then
      Lines.Add(Format('… %d weitere Befunde', [Count - MaxFindings]));
    Lines.Insert(0, Format('%d Befunde in %d Dateien.', [Count, Checked]));
    Result := TrimRight(Lines.Text);
  finally
    Lines.Free;
  end;
end;

function SplitKeepingBreaks(const AText: string): TArray<string>;
var
  Index, Start: Integer;
begin
  // Jede Zeile behält ihren Zeilenwechsel, damit CRLF/LF erhalten bleiben.
  Result := nil;
  Start := 1;
  for Index := 1 to Length(AText) do
    if AText[Index] = #10 then
    begin
      Result := Result + [Copy(AText, Start, Index - Start + 1)];
      Start := Index + 1;
    end;
  if Start <= Length(AText) then
    Result := Result + [Copy(AText, Start, MaxInt)];
end;

function LineBreakIn(const AText: string): string;
begin
  if Pos(#13#10, AText) > 0 then
    Result := #13#10
  else
    Result := #10;
end;

class function TMcpCodeTools.ReplaceLines(const AOriginal, AText: string; AStartLine, AEndLine: Integer): string;
var
  Lines: TArray<string>;
  Index: Integer;
  Inserted: string;
begin
  Lines := SplitKeepingBreaks(AOriginal);
  if (AStartLine < 1) or (AStartLine > Length(Lines) + 1) or (AEndLine < AStartLine - 1) or
    (AEndLine > Length(Lines)) then
    raise EMcpToolError.CreateFmt('Ungültiger Bereich %d-%d; die Datei hat %d Zeilen',
      [AStartLine, AEndLine, Length(Lines)]);
  Inserted := AText;
  // Der ersetzte Bereich endet mit einem Zeilenwechsel, wenn danach noch etwas kommt.
  if (Inserted <> '') and (AEndLine < Length(Lines)) and not EndsStr(#10, Inserted) then
    Inserted := Inserted + LineBreakIn(AOriginal);
  Result := '';
  for Index := 0 to AStartLine - 2 do
    Result := Result + Lines[Index];
  Result := Result + Inserted;
  for Index := AEndLine to High(Lines) do
    Result := Result + Lines[Index];
end;

function TMcpCodeTools.CheckCode(const ARules: TArray<IRule>; const ASettings: TServerSettings;
  const ARoot, AFileName, AText: string; AStartLine, AEndLine: Integer): string;
var
  Lines: TStringList;
  Original, NewText, RelativePath: string;
  Finding: TRuleFinding;
  Count: Integer;
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
  Name: TUnresolvedName;
  Unresolved: TArray<TUnresolvedName>;
  CheckNames: Boolean;
begin
  if AStartLine > 0 then
  begin
    if not (Assigned(FReadText) and FReadText(AFileName, Original)) then
      raise EMcpToolError.CreateFmt('%s ist nicht lesbar; ohne Bereich den ganzen Text angeben', [AFileName]);
    NewText := ReplaceLines(Original, AText, AStartLine, AEndLine);
  end
  else
    NewText := AText;
  RelativePath := AFileName;
  if (ARoot <> '') and StartsText(IncludeTrailingPathDelimiter(ARoot), AFileName) then
    RelativePath := Copy(AFileName, Length(IncludeTrailingPathDelimiter(ARoot)) + 1, MaxInt);
  Lines := TStringList.Create;
  try
    Count := 0;
    for Finding in TFileChecker.CheckText(ARules, ASettings, RelativePath, NewText) do
    begin
      Inc(Count);
      if Count <= MaxFindings then
        Lines.Add(Format('%d:%d: %s [%s] [Konfidenz %s] %s', [Finding.Range.StartPos.Line + 1,
          Finding.Range.StartPos.Character + 1, TFindingsOutput.SeverityName(Finding.Severity), Finding.RuleId,
          ConfidenceText(Finding.Confidence), Finding.Message]));
    end;
    CheckNames := TUnresolvedNames.Available(FIndex);
    if CheckNames then
    begin
      Tree := TSyntaxTreeCache.Parse(NewText);
      try
        Resolver := TNameResolver.Create(FIndex, FEnsureUnit);
        try
          Resolver.Namespaces := FNamespaces;
          Unresolved := TUnresolvedNames.Find(Resolver, Tree, AFileName);
        finally
          Resolver.Free;
        end;
      finally
        Tree.Free;
      end;
      for Name in Unresolved do
      begin
        Inc(Count);
        if Count <= MaxFindings then
          Lines.Add(Format('%d:%d: warning [unresolved-identifier] "%s" ist nicht auflösbar', [Name.Range.StartPos.Line + 1,
            Name.Range.StartPos.Character + 1, Name.Name]));
      end;
    end;
    if Count > MaxFindings then
      Lines.Add(Format('… %d weitere Befunde', [Count - MaxFindings]));
    if Count = 0 then
      Lines.Insert(0, Format('Keine Befunde in %s.', [ExtractFileName(AFileName)]))
    else
      Lines.Insert(0, Format('%d Befunde in %s (Positionen im neuen Text, Zeile:Spalte):', [Count, ExtractFileName(AFileName)]));
    if not CheckNames then
      Lines.Add('Hinweis: Unit System ist nicht im Index, Bezeichner wurden nicht geprüft.')
    else
      Lines.Add('Hinweis: Die Namensprüfung kennt keine Überladungen, Generics, Class Helper und with; ' +
        'einzelne Meldungen können Fehlalarme sein.');
    Result := TrimRight(Lines.Text);
  finally
    Lines.Free;
  end;
end;

class function TMcpCodeTools.ParseDirection(const AText: string): TMcpCallDirection;
begin
  if SameText(AText, 'incoming') then
    Result := TMcpCallDirection.Incoming
  else if SameText(AText, 'outgoing') then
    Result := TMcpCallDirection.Outgoing
  else
    Result := TMcpCallDirection.Both;
end;

end.
