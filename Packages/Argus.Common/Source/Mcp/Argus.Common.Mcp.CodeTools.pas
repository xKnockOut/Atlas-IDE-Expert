unit Argus.Common.Mcp.CodeTools;

// MCP-Werkzeuge, die Quelltext auswerten (#48): Verwendungen, Aufrufhierarchie
// und Befunde der Prüfregeln. Das Symbol wird per Name über den Index gefunden
// und dann wie im LSP an seiner Deklaration aufgelöst.

interface

uses
  System.SysUtils,
  Argus.Common.Index.Contract,
  Argus.Common.Configuration.Contract,
  Argus.Common.Rules.Contract,
  Argus.Common.Semantics.NameResolver,
  Argus.Common.Lsp.References;

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
    /// <summary>Befunde der Prüfregeln und Syntaxfehler je Datei; ARoot für relative Pfade.</summary>
    class function Diagnostics(const ARules: TArray<IRule>; const ASettings: TServerSettings;
      const ARoot: string; const AFiles: TArray<string>; const AReadText: TReferenceReadText): string; static;
    class function ParseDirection(const AText: string): TMcpCallDirection; static;
    property Namespaces: TArray<string> read FNamespaces write FNamespaces;
  end;

implementation

uses
  System.Classes,
  System.StrUtils,
  Argus.Common.Documents.Contract,
  Argus.Common.Pascal.SyntaxTree,
  Argus.Common.Pascal.Parser,
  Argus.Common.Lsp.Hierarchies,
  Argus.Common.Rules.Checker,
  Argus.Common.Rules.Output,
  Argus.Common.Mcp.IndexTools;

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
  Tree := TPascalParser.Parse(Text);
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
    Tree := TPascalParser.Parse(Text);
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
          Lines.Add(Format('%s:%d:%d: %s [%s] %s', [FileName, Finding.Range.StartPos.Line + 1,
            Finding.Range.StartPos.Character + 1, TFindingsOutput.SeverityName(Finding.Severity),
            Finding.RuleId, Finding.DisplayMessage]));
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
