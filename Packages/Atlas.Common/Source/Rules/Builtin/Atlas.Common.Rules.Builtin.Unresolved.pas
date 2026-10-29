unit Atlas.Common.Rules.Builtin.Unresolved;

// Nicht auflösbare Bezeichner beim Tippen (#178), wie Compilerfehler E2003,
// aber ohne Compiler (Community Edition, Prüfung in der IDE aus). Nutzt die
// vorsichtige Prüfung aus TUnresolvedNames: nur der erste Name einer Kette in
// Anweisungen, with/asm/anonyme Methoden übersprungen, ohne Unit System im
// Index keine Aussage. Ohne Index (Linter) schweigt die Regel.
//
// uses-unit-not-found (#1016, wie F2613, F1026, F1027, E2202, F2092): Units in
// uses und contains, die der Compiler nicht findet (TRuleContext.Units, die
// Suche steht in Atlas.Common.Projects.UnitLookup), Dateien aus "in '…'",
// Packages aus requires und Units, die sich selbst einbinden. Findet die Suche
// nicht einmal System, fehlt der Bibliothekspfad: eine Meldung F1027 statt
// einer je Unit. Einträge in {$IF…}-Blöcken bleiben still, ebenso alles, worüber
// die Suche keine sichere Aussage trifft (Installation unbekannt, Makro im
// Pfad). Korrekturen: Namen mit Namespace bzw. ähnlich geschriebene Units
// einsetzen, Ordner außerhalb der Suchpfade in DCC_UnitSearchPath der .dproj
// aufnehmen.
//
// unresolved-attribute (#1019, wie W1074, E2289): Ein Attribut [Name] lässt
// sich weder als Klasse NameAttribute noch als Name auflösen; Delphi warnt nur
// und übergeht es (DUnitX-Tests laufen dann nicht). Vorgeschlagen wird die Unit,
// die den Typ im Index deklariert; Fassaden-Units, die ihn aus einer anderen
// Kandidaten-Unit weiterreichen (DUnitX.TestFramework), gehen vor. Ohne System
// im Index, wenn eine Unit aus uses nicht im Index steht (sie könnte das
// Attribut deklarieren), in {$IF…}-Blöcken und bei unbekannten Vorfahren bleibt
// die Regel still; Attribute des Compilers (Weak, Unsafe, Ref …) zählen immer.
//
// unresolved-type (#1031, wie E2003, E2564, E2005): Ein Typname in einer
// Deklaration (Feld, Parameter, Ergebnis, Vorfahr, Interface-Liste, Variable,
// Typargument) lässt sich nicht auflösen bzw. bezeichnet keinen Typ. Dieselben
// Vorbedingungen wie bei unresolved-attribute (System im Index, alle Units aus
// uses bekannt, nicht in {$IF…}); außerdem still bei Typparametern, Namen, die
// die Datei irgendwo als Typ deklariert (auch verschachtelt), und Namen, die der
// Index als verschachtelten Typ kennt (geerbte innere Typen). Korrektur: die
// Unit, die den Typ im Index deklariert, in uses aufnehmen.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

type
{$SCOPEDENUMS ON}
  TUsesListKind = (UsedUnit, ContainedUnit, RequiredPackage);
{$SCOPEDENUMS OFF}

  /// <summary>Eintrag einer uses-, contains- oder requires-Liste (#1016).</summary>
  TUsesListEntry = record
    Kind: TUsesListKind;
    Name: string;
    /// <summary>Pfad aus "in '…'" ohne Hochkommas; '' ohne.</summary>
    InPath: string;
    /// <summary>Alle Namensteile.</summary>
    Range: TTextRange;
  end;

  TUnresolvedAttributeRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Units, die AName bzw. ANameAttribute als Typ deklarieren, ohne die, die eine andere Kandidaten-Unit
    /// im interface einbindet und weiterreicht; sortiert.</summary>
    class function DeclaringUnits(const AIndex: ISymbolIndex; const AName: string): TArray<string>; static;
  end;

  TUsesUnitNotFoundRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Alle Einträge aus uses, contains und requires in Quelltextreihenfolge.</summary>
    class function Entries(const ATokens: TArray<TPascalToken>): TArray<TUsesListEntry>; static;
    /// <summary>Bekannte Units, die AName meinen könnten: zuerst mit Namespace davor (Forms → Vcl.Forms),
    /// dann ähnlich geschriebene (Editierabstand höchstens 2), höchstens drei.</summary>
    class function Suggestions(const AName: string; const AKnown: TArray<string>): TArray<string>; static;
    /// <summary>Kleinste Ersetzung, die AOld in ANew verwandelt (gemeinsamer Anfang und Schluss bleiben).</summary>
    class function DiffEdit(const AOld, ANew: string): TTextEdit; static;
  end;

  TUnresolvedTypeRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Units, die den Typ AName auf oberster Ebene deklarieren (bei AArity &gt; 0 mit so vielen
    /// Typparametern), ohne AOwnUnit und ohne Units, die eine andere Kandidatin im interface weiterreichen;
    /// sortiert.</summary>
    class function DeclaringUnits(const AIndex: ISymbolIndex; const AName, AOwnUnit: string;
      AArity: Integer): TArray<string>; static;
  end;

procedure RegisterUnresolvedRules(ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Text.Lines,
  Atlas.Text.Fuzzy,
  Atlas.Common.Rules.Options,
  Atlas.Common.Projects.DprojEditor,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.Attributes,
  Atlas.Common.Semantics.UnresolvedNames;

type
  TUnresolvedIdentifierRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

function TUnresolvedIdentifierRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('unresolved-identifier', TRuleSeverity.Warning,
    'Bezeichner ist im Projekt und seinen Units nicht deklariert (wie Compilerfehler E2003).');
end;

procedure TUnresolvedIdentifierRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Resolver: TNameResolver;
  Name: TUnresolvedName;
begin
  if (AContext.Tree = nil) or not TUnresolvedNames.Available(AContext.Index) then
    Exit;
  Resolver := TNameResolver.Create(AContext.Index, AContext.EnsureUnit, AContext.TreeUnits);
  try
    Resolver.Namespaces := AContext.Namespaces;
    for Name in TUnresolvedNames.Find(Resolver, AContext.Tree, AContext.RelativePath) do
      if Name.Suggestion <> '' then
        AReport.Add(Name.Range, Format('"%s" ist nicht deklariert; gemeint ist %s? ({$SCOPEDENUMS ON})',
          [Name.Name, Name.Suggestion]), TRuleConfidence.Medium)
      else
        AReport.Add(Name.Range, Format('"%s" ist nicht deklariert', [Name.Name]), TRuleConfidence.Medium);
  finally
    Resolver.Free;
  end;
end;

{ TUsesUnitNotFoundRule }

function TUsesUnitNotFoundRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('uses-unit-not-found', TRuleSeverity.Error,
    'Unit in uses nicht gefunden (wie F2613)');
end;

function IsCode(const AToken: TPascalToken): Boolean;
begin
  Result := not (AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]);
end;

/// <summary>Text eines String-Literals ohne Hochkommas ('' → ').</summary>
function Unquoted(const AText: string): string;
begin
  Result := AText;
  if (Length(Result) >= 2) and (Result[1] = '''') and (Result[Length(Result)] = '''') then
    Result := Copy(Result, 2, Length(Result) - 2);
  Result := StringReplace(Result, '''''', '''', [rfReplaceAll]);
end;

class function TUsesUnitNotFoundRule.Entries(const ATokens: TArray<TPascalToken>): TArray<TUsesListEntry>;
var
  Index, Previous, First, Last: Integer;
  Kind: TUsesListKind;
  Entry: TUsesListEntry;
  Name, InPath: string;
  AfterIn: Boolean;
  IsPackage: Boolean;
begin
  Result := nil;
  // contains und requires gibt es nur in einer Package-Quelle (beginnt mit "package"). In einer Unit sind es
  // Bezeichner, etwa Felder eines Records ("Requires: TArray<TPackageEntry>;" nach einem Semikolon).
  IsPackage := False;
  for Index := 0 to High(ATokens) do
    if IsCode(ATokens[Index]) then
    begin
      IsPackage := SameText(ATokens[Index].Text, 'package');
      Break;
    end;
  Index := 0;
  Previous := -1;
  while Index <= High(ATokens) do
  begin
    if not IsCode(ATokens[Index]) then
    begin
      Inc(Index);
      Continue;
    end;
    // uses überall; contains und requires nur in Packages am Anfang einer Anweisung (sonst ein Bezeichner).
    if ATokens[Index].IsKeyword('uses') then
      Kind := TUsesListKind.UsedUnit
    else if IsPackage and (ATokens[Index].Kind = TPascalTokenKind.Identifier) and (Previous >= 0) and
      ATokens[Previous].IsSymbol(';') and SameText(ATokens[Index].Text, 'contains') then
      Kind := TUsesListKind.ContainedUnit
    else if IsPackage and (ATokens[Index].Kind = TPascalTokenKind.Identifier) and (Previous >= 0) and
      ATokens[Previous].IsSymbol(';') and SameText(ATokens[Index].Text, 'requires') then
      Kind := TUsesListKind.RequiredPackage
    else
    begin
      Previous := Index;
      Inc(Index);
      Continue;
    end;
    Name := '';
    InPath := '';
    First := -1;
    Last := -1;
    AfterIn := False;
    Inc(Index);
    while Index <= High(ATokens) do
    begin
      if ATokens[Index].IsSymbol(';') or ATokens[Index].IsSymbol(',') then
      begin
        if Name <> '' then
        begin
          Entry.Kind := Kind;
          Entry.Name := Name;
          Entry.InPath := InPath;
          Entry.Range := TTextRange.Create(ATokens[First].StartPos, ATokens[Last].EndPos);
          Result := Result + [Entry];
        end;
        Name := '';
        InPath := '';
        First := -1;
        AfterIn := False;
        if ATokens[Index].IsSymbol(';') then
          Break;
      end
      else if ATokens[Index].IsKeyword('in') then
        AfterIn := True
      else if AfterIn and (ATokens[Index].Kind = TPascalTokenKind.StringLiteral) then
        InPath := Unquoted(ATokens[Index].Text)
      else if not AfterIn and ((ATokens[Index].Kind = TPascalTokenKind.Identifier) or
        ATokens[Index].IsSymbol('.')) then
      begin
        if First < 0 then
          First := Index;
        Last := Index;
        Name := Name + ATokens[Index].Text;
      end;
      Inc(Index);
    end;
    Previous := Index;
    Inc(Index);
  end;
end;

type
  TScoredName = record
    Score: Integer;
    Name: string;
  end;

function Scored(AScore: Integer; const AName: string): TScoredName;
begin
  Result.Score := AScore;
  Result.Name := AName;
end;

class function TUsesUnitNotFoundRule.Suggestions(const AName: string; const AKnown: TArray<string>): TArray<string>;
const
  MaxSuggestions = 3;
  MaxDistance = 2;
var
  Qualified: TList<string>;
  Similar: TList<TScoredName>;
  Known: string;
  Score: Integer;
  Item: TScoredName;
  Order: IComparer<TScoredName>;
begin
  Result := nil;
  Qualified := TList<string>.Create;
  Similar := TList<TScoredName>.Create;
  try
    for Known in AKnown do
    begin
      if SameText(Known, AName) then
        Continue;
      if EndsText('.' + AName, Known) then
        Qualified.Add(Known)
      else
      begin
        Score := TTextFuzzy.EditDistance(AName, Known, MaxDistance);
        if Score <= MaxDistance then
          Similar.Add(Scored(Score, Known));
      end;
    end;
    Qualified.Sort;
    Order := TComparer<TScoredName>.Construct(
      function(const ALeft, ARight: TScoredName): Integer
      begin
        Result := ALeft.Score - ARight.Score;
        if Result = 0 then
          Result := CompareText(ALeft.Name, ARight.Name);
      end);
    Similar.Sort(Order);
    for Known in Qualified do
      if Length(Result) < MaxSuggestions then
        Result := Result + [Known];
    for Item in Similar do
      if Length(Result) < MaxSuggestions then
        Result := Result + [Item.Name];
  finally
    Similar.Free;
    Qualified.Free;
  end;
end;

/// <summary>Position des Zeichens AOffset (ab 0) in AText.</summary>
function PositionOf(const AText: string; AOffset: Integer): TTextPosition;
var
  Index: Integer;
begin
  Result := TTextPosition.Create(0, 0);
  for Index := 1 to AOffset do
    if AText[Index] = #10 then
      Result := TTextPosition.Create(Result.Line + 1, 0)
    else
      Result := TTextPosition.Create(Result.Line, Result.Character + 1);
end;

class function TUsesUnitNotFoundRule.DiffEdit(const AOld, ANew: string): TTextEdit;
var
  Prefix, Suffix: Integer;
begin
  Prefix := 0;
  while (Prefix < Length(AOld)) and (Prefix < Length(ANew)) and (AOld[Prefix + 1] = ANew[Prefix + 1]) do
    Inc(Prefix);
  Suffix := 0;
  while (Suffix < Length(AOld) - Prefix) and (Suffix < Length(ANew) - Prefix) and
    (AOld[Length(AOld) - Suffix] = ANew[Length(ANew) - Suffix]) do
    Inc(Suffix);
  Result := TTextEdit.Create(TTextRange.Create(PositionOf(AOld, Prefix), PositionOf(AOld, Length(AOld) - Suffix)),
    Copy(ANew, Prefix + 1, Length(ANew) - Prefix - Suffix));
end;

/// <summary>"A", "A, B", "A, B oder C".</summary>
function Alternatives(const AItems: TArray<string>): string;
var
  Index: Integer;
begin
  Result := '';
  for Index := 0 to High(AItems) do
  begin
    if Index = 0 then
      Result := AItems[Index]
    else if Index = High(AItems) then
      Result := Result + ' oder ' + AItems[Index]
    else
      Result := Result + ', ' + AItems[Index];
  end;
end;

/// <summary>Zeilen innerhalb von {$IF…}…{$ENDIF}: Element I gilt für Zeile I.</summary>
function ConditionalLines(const ATokens: TArray<TPascalToken>): TArray<Boolean>;
var
  Token: TPascalToken;
  Text: string;
  Depth, Line, LastLine, StartLine: Integer;
begin
  LastLine := 0;
  for Token in ATokens do
    LastLine := Token.EndPos.Line;
  SetLength(Result, LastLine + 1);
  Depth := 0;
  StartLine := 0;
  for Token in ATokens do
  begin
    if Token.Kind <> TPascalTokenKind.Directive then
      Continue;
    Text := UpperCase(Token.Text);
    if StartsStr('{$IF', Text) or StartsStr('(*$IF', Text) then
    begin
      if Depth = 0 then
        StartLine := Token.StartPos.Line;
      Inc(Depth);
    end
    else if (Depth > 0) and (StartsStr('{$ENDIF', Text) or StartsStr('{$IFEND', Text) or
      StartsStr('(*$ENDIF', Text) or StartsStr('(*$IFEND', Text)) then
    begin
      Dec(Depth);
      if Depth = 0 then
        for Line := StartLine to Token.EndPos.Line do
          Result[Line] := True;
    end;
  end;
  if Depth > 0 then
    for Line := StartLine to LastLine do
      Result[Line] := True;
end;

/// <summary>Quelle der Suche aus der Option searchPaths: project (Vorgabe), atlas oder both.</summary>
function SourcesOf(const AOptions: string): TRuleUnitSources;
var
  Value: string;
begin
  Value := TRuleOptions.Text(AOptions, 'searchPaths', 'project');
  if SameText(Value, 'atlas') then
    Result := [TRuleUnitSource.Atlas]
  else if SameText(Value, 'both') then
    Result := [TRuleUnitSource.Project, TRuleUnitSource.Atlas]
  else
    Result := [TRuleUnitSource.Project];
end;

procedure TUsesUnitNotFoundRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  List: TArray<TUsesListEntry>;
  Entry: TUsesListEntry;
  Lines: TArray<Boolean>;
  Own, Folder, ProjectFile, ProjectText, NewText, Key, Suggestion: string;
  Index: Integer;
  Sources: TRuleUnitSources;
  Known, Suggested: TArray<string>;
  HasKnown: Boolean;
  Fixes: TArray<TRuleFix>;
  Fix: TRuleFix;
  Edit: TTextEdit;
begin
  if AContext.Tree = nil then
    Exit;
  List := Entries(AContext.Tree.Tokens);
  Lines := ConditionalLines(AContext.Tree.Tokens);
  // F2092: eine Unit, die sich selbst einbindet; braucht keine Pfade.
  Own := TUsesClauses.OwnName(AContext.Tree.Tokens);
  for Entry in List do
    if (Entry.Kind <> TUsesListKind.RequiredPackage) and (Own <> '') and SameText(Entry.Name, Own) then
      AReport.Add(Entry.Range, Format('%s verwendet sich selbst (wie F2092).', [Entry.Name]));
  if AContext.Units = nil then
    Exit;
  Sources := SourcesOf(AContext.Options);
  // F1027: Ohne System fehlt der Bibliothekspfad; dann eine Meldung statt einer je Unit.
  if AContext.Units.Find('System', '', AContext.FileName, [TRuleUnitSource.Project]) = TRuleUnitAnswer.Missing then
  begin
    if Length(List) > 0 then
      AReport.Add(List[0].Range, 'Unit System nicht gefunden; der Bibliothekspfad der Installation fehlt ' +
        '(wie F1027).');
    Exit;
  end;
  HasKnown := False;
  Known := nil;
  for Entry in List do
  begin
    if (Entry.Range.StartPos.Line <= High(Lines)) and Lines[Entry.Range.StartPos.Line] then
      Continue;
    if (Own <> '') and SameText(Entry.Name, Own) then
      Continue;
    if Entry.Kind = TUsesListKind.RequiredPackage then
    begin
      if AContext.Units.FindPackage(Entry.Name) = TRuleUnitAnswer.Missing then
        AReport.Add(Entry.Range, Format('Package %s nicht gefunden (wie E2202).', [Entry.Name]));
      Continue;
    end;
    if AContext.Units.Find(Entry.Name, Entry.InPath, AContext.FileName, Sources) <> TRuleUnitAnswer.Missing then
      Continue;
    if Entry.InPath <> '' then
    begin
      AReport.Add(Entry.Range, Format('Datei %s für %s nicht gefunden (wie F1026).', [Entry.InPath, Entry.Name]));
      Continue;
    end;
    if not HasKnown then
    begin
      Known := AContext.Units.KnownUnits(Sources);
      HasKnown := True;
    end;
    Suggested := Suggestions(Entry.Name, Known);
    Fixes := nil;
    for Suggestion in Suggested do
      Fixes := Fixes + [TRuleFix.Create(Format('%s verwenden', [Suggestion]),
        [TTextEdit.Create(Entry.Range, Suggestion)])];
    // Ordner unter dem Projekt, der in keinem Suchpfad steht: in DCC_UnitSearchPath der Basis aufnehmen.
    Folder := AContext.Units.FolderOutsidePaths(Entry.Name);
    if (Folder <> '') and AContext.Units.ReadProject(ProjectFile, ProjectText) then
    begin
      Key := TDprojEditor.ConfigKey(ProjectText, 'Base');
      if (Key <> '') and (TDprojEditor.AddToList(ProjectText, Key, 'DCC_UnitSearchPath', Folder, NewText) =
        TDprojEditResult.Added) then
      begin
        Edit := DiffEdit(ProjectText, NewText);
        Fix := TRuleFix.Create(Format('Ordner %s in den Suchpfad aufnehmen', [Folder]), [Edit]);
        Fix.FileName := ProjectFile;
        Fixes := [Fix] + Fixes;
      end;
    end;
    // Mehrere gleichwertige Vorschläge: keiner bevorzugt.
    if Length(Fixes) > 1 then
      for Index := 0 to High(Fixes) do
        Fixes[Index].Alternative := True;
    if Folder <> '' then
      AReport.Add(Entry.Range, Format('Unit %s nicht gefunden; sie liegt in %s außerhalb der Suchpfade (wie F2613).',
        [Entry.Name, Folder]), TRuleConfidence.High, Fixes)
    else if Length(Suggested) > 0 then
      AReport.Add(Entry.Range, Format('Unit %s nicht gefunden; ähnlich: %s (wie F2613).',
        [Entry.Name, Alternatives(Suggested)]), TRuleConfidence.High, Fixes)
    else
      AReport.Add(Entry.Range, Format('Unit %s nicht gefunden (wie F2613).', [Entry.Name]));
  end;
end;

{ TUnresolvedAttributeRule }

const
  // Attribute, die der Compiler selbst kennt (System); sie fehlen in einem unvollständigen Index.
  CompilerAttributes: array[0..8] of string = ('Weak', 'Unsafe', 'Ref', 'Volatile', 'Align', 'HPPGEN', 'HFA',
    'Stored', 'Result');
  // DUnitX-Attribute: ohne sie laufen die Tests nicht. Unit, falls DUnitX nicht im Index steht.
  DUnitXAttributes: array[0..16] of string = ('TestFixture', 'Test', 'TestCase', 'Setup', 'TearDown',
    'SetupFixture', 'TearDownFixture', 'Ignore', 'Category', 'WillRaise', 'WillRaiseAny', 'RepeatTest', 'MaxTime',
    'TestCaseProvider', 'TestInOwnThread', 'IgnoreMemoryLeaks', 'AutoNameTestCase');
  DUnitXUnit = 'DUnitX.TestFramework';

function TUnresolvedAttributeRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('unresolved-attribute', TRuleSeverity.Error,
    'Attribut nicht gefunden und vom Compiler still ignoriert (wie W1074)');
end;

class function TUnresolvedAttributeRule.DeclaringUnits(const AIndex: ISymbolIndex; const AName: string): TArray<string>;
var
  Candidates: TList<string>;
  Location: TSymbolLocation;
  Name, Other: string;
  Found: TUnitIndex;
  Used: Boolean;
begin
  Result := nil;
  if AIndex = nil then
    Exit;
  Candidates := TList<string>.Create;
  try
    for Name in TAttributes.ClassNames(AName) do
      for Location in AIndex.FindSymbols(Name) do
        if (Location.Symbol.Container = '') and (Location.Symbol.Kind in [TIndexSymbolKind.ClassType,
          TIndexSymbolKind.TypeAlias]) and not Candidates.Contains(Location.UnitName) then
          Candidates.Add(Location.UnitName);
    // Fassade vor Quelle: eine Unit, die eine andere Kandidatin im interface einbindet, reicht den Typ weiter.
    for Name in Candidates do
    begin
      Used := False;
      for Other in Candidates do
        if not SameText(Other, Name) and AIndex.FindUnit(Other, Found) and
          (IndexText(Name, Found.InterfaceUses) >= 0) then
          Used := True;
      if not Used then
        Result := Result + [Name];
    end;
    TArray.Sort<string>(Result);
  finally
    Candidates.Free;
  end;
end;

/// <summary>Offset ab 0 des ersten Tokens an APosition; 0 ohne.</summary>
function OffsetAt(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition): Integer;
var
  Token: TPascalToken;
begin
  for Token in ATokens do
    if (Token.StartPos.Line = APosition.Line) and (Token.StartPos.Character = APosition.Character) then
      Exit(Token.Offset);
  Result := 0;
end;

procedure TUnresolvedAttributeRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Resolver: TNameResolver;
  Lines: TArray<Boolean>;
  LineBreak: string;
  Level: TRuleConfidence;

  procedure CheckItem(AItem: TSyntaxNode);
  var
    NameNode: TSyntaxNode;
    Use: TAttributeUse;
    Names: TArray<string>;
    Resolved: TResolvedSymbol;
    Units: TArray<string>;
    UnitName, Message, Bare: string;
    Fixes: TArray<TRuleFix>;
    Fix: TRuleFix;
    Edit: TTextEdit;
    Index: Integer;
  begin
    NameNode := AItem;
    if (AItem.Kind = TSyntaxKind.Call) and (AItem.ChildCount > 0) then
      NameNode := AItem[0];
    if not (NameNode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) or
      not TAttributes.At(AContext.Tree, NameNode.StartPos, Use) then
      Exit;
    Bare := Copy(Use.Name, LastDelimiter('.', Use.Name) + 1, MaxInt);
    if MatchText(Bare, CompilerAttributes) or MatchText(Bare + 'Attribute', CompilerAttributes) then
      Exit;
    // Zuerst NameAttribute, dann Name, wie der Compiler.
    Names := Use.Name.Split(['.']);
    Names[High(Names)] := Names[High(Names)] + 'Attribute';
    Resolved := Resolver.ResolveChain(AContext.Tree, AContext.RelativePath, Names, NameNode.StartOffset);
    if Resolved.Found or Resolver.HasUnknownAncestor then
      Exit;
    Resolved := Resolver.ResolveChain(AContext.Tree, AContext.RelativePath, Use.Name.Split(['.']),
      NameNode.StartOffset);
    if Resolved.Found or Resolver.HasUnknownAncestor or Resolver.IsUnitPrefix(Use.Name) then
      Exit;
    Units := DeclaringUnits(AContext.Index, Bare);
    if (Length(Units) = 0) and MatchText(Bare, DUnitXAttributes) then
      Units := [DUnitXUnit];
    Message := Format('Attribut %s nicht gefunden und wird ignoriert', [Use.Name]);
    if MatchText(Bare, DUnitXAttributes) or ((Length(Units) > 0) and StartsText('DUnitX', Units[0])) then
      Message := Message + '; die Tests laufen nicht';
    Message := Message + ' (wie W1074).';
    if Length(Units) = 1 then
      Message := Message + Format(' Unit %s fehlt.', [Units[0]])
    else if Length(Units) > 1 then
      Message := Message + Format(' In Frage kommen %s.', [Alternatives(Units)]);
    Fixes := nil;
    for UnitName in Units do
      if TUsesClauses.AddUnit(AContext.Tree.Tokens, OffsetAt(AContext.Tree.Tokens, NameNode.StartPos), UnitName,
        LineBreak, Edit) then
      begin
        Fix := TRuleFix.Create(Format('uses %s ergänzen', [UnitName]), [Edit]);
        Fixes := Fixes + [Fix];
      end;
    if Length(Fixes) > 1 then
      for Index := 0 to High(Fixes) do
        Fixes[Index].Alternative := True;
    AReport.Add(Use.NameRange, Message, Level, Fixes);
  end;

  // Iterativ (Bericht M1).
  procedure Visit(ARoot: TSyntaxNode);
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Index: Integer;
  begin
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Node.Kind = TSyntaxKind.Attribute then
        begin
          if (Node.StartPos.Line <= High(Lines)) and Lines[Node.StartPos.Line] then
            Continue;
          for Index := 0 to Node.ChildCount - 1 do
            CheckItem(Node[Index]);
          Continue;
        end;
        // In Anweisungen gibt es keine Attribute.
        if Node.Kind in [TSyntaxKind.Block, TSyntaxKind.AsmBlock] then
          Continue;
        for Index := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

var
  Token: TPascalToken;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or not TUnresolvedNames.Available(AContext.Index) or
    not TUnresolvedNames.UsesKnown(AContext.Index, TUsesClauses.UsedUnits(AContext.Tree.Tokens),
    AContext.Namespaces, AContext.EnsureUnit) then
    Exit;
  Lines := ConditionalLines(AContext.Tree.Tokens);
  LineBreak := TTextLines.LineBreakOf(AContext.Text);
  // Mit Include-Dateien kann das Attribut dort deklariert sein.
  Level := TRuleConfidence.High;
  for Token in AContext.Tree.Tokens do
    if (Token.Kind = TPascalTokenKind.Directive) and (StartsText('{$I ', Token.Text) or
      StartsText('{$INCLUDE ', Token.Text)) then
      Level := TRuleConfidence.Medium;
  Resolver := TNameResolver.Create(AContext.Index, AContext.EnsureUnit, AContext.TreeUnits);
  try
    Resolver.Namespaces := AContext.Namespaces;
    Resolver.PinTree(AContext.Tree, AContext.RelativePath);
    try
      Visit(AContext.Tree.Root);
    finally
      Resolver.UnpinTree;
    end;
  finally
    Resolver.Free;
  end;
end;

{ TUnresolvedTypeRule }

const
  // Typen, die der Compiler kennt, ohne dass System.pas sie deklariert.
  CompilerTypes: array[0..7] of string = ('ByteBool', 'WordBool', 'LongBool', 'Comp', 'Real48', 'OpenString',
    'PShortString', 'Extended80');
  TypeKinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType,
    TIndexSymbolKind.InterfaceType, TIndexSymbolKind.HelperType, TIndexSymbolKind.EnumType,
    TIndexSymbolKind.TypeAlias];

function TUnresolvedTypeRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('unresolved-type', TRuleSeverity.Error, 'Typ in einer Deklaration nicht gefunden');
end;

class function TUnresolvedTypeRule.DeclaringUnits(const AIndex: ISymbolIndex; const AName, AOwnUnit: string;
  AArity: Integer): TArray<string>;
var
  Candidates: TList<string>;
  Location: TSymbolLocation;
  Name, Other: string;
  Found: TUnitIndex;
  Used: Boolean;
  Arity: Integer;
begin
  Result := nil;
  if AIndex = nil then
    Exit;
  Candidates := TList<string>.Create;
  try
    for Location in AIndex.FindSymbols(AName) do
    begin
      if (Location.Symbol.Container <> '') or not (Location.Symbol.Kind in TypeKinds) or
        not Location.Symbol.InInterface or SameText(Location.UnitName, AOwnUnit) or
        Candidates.Contains(Location.UnitName) then
        Continue;
      Arity := 0;
      if Location.Symbol.TypeParams <> '' then
        Arity := Length(Location.Symbol.TypeParams.Split([',']));
      if Arity = AArity then
        Candidates.Add(Location.UnitName);
    end;
    // Fassade vor Quelle wie bei unresolved-attribute.
    for Name in Candidates do
    begin
      Used := False;
      for Other in Candidates do
        if not SameText(Other, Name) and AIndex.FindUnit(Other, Found) and
          (IndexText(Name, Found.InterfaceUses) >= 0) then
          Used := True;
      if not Used then
        Result := Result + [Name];
    end;
    TArray.Sort<string>(Result);
  finally
    Candidates.Free;
  end;
end;

procedure TUnresolvedTypeRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Resolver: TNameResolver;
  Lines: TArray<Boolean>;
  LineBreak, OwnUnit: string;
  Level: TRuleConfidence;
  // Typnamen und Typparameter der Datei: gelten als bekannt.
  Declared: TDictionary<string, Boolean>;

  // Iterativ (Bericht M1).
  procedure Collect(ARoot: TSyntaxNode);
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Index: Integer;
  begin
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if (Node.Kind in [TSyntaxKind.TypeDecl, TSyntaxKind.ForwardType]) and (Node.Name <> '') then
          Declared.AddOrSetValue(LowerCase(Node.Name), True)
        else if Node.Kind = TSyntaxKind.GenericParams then
          for Index := 0 to Node.ChildCount - 1 do
            Declared.AddOrSetValue(LowerCase(Node[Index].Name), True);
        for Index := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

  /// <summary>Kennt der Index AName als verschachtelten Typ (geerbte innere Typen sind ohne Präfix sichtbar)?
  /// </summary>
  function NestedSomewhere(const AName: string): Boolean;
  var
    Location: TSymbolLocation;
  begin
    for Location in AContext.Index.FindSymbols(AName) do
      if (Location.Symbol.Container <> '') and (Location.Symbol.Kind in TypeKinds) then
        Exit(True);
    Result := False;
  end;

  procedure CheckReference(ANode: TSyntaxNode);
  var
    Names: TArray<string>;
    Bare, Message, UnitName: string;
    Resolved: TResolvedSymbol;
    Units: TArray<string>;
    Fixes: TArray<TRuleFix>;
    Fix: TRuleFix;
    Edit: TTextEdit;
    Args: TSyntaxNode;
    Arity, Index: Integer;
    Range: TTextRange;
  begin
    // Der Anfang eines Teilbereichs (MinWert..MaxWert) ist ein Ausdruck, kein Typ.
    if (ANode.Name = '') or MatchText(ANode.Name, ['string', 'file', 'const']) or
      ((ANode.Parent <> nil) and (ANode.Parent.Kind = TSyntaxKind.SubrangeType)) then
      Exit;
    Names := ANode.Name.Split(['.']);
    Bare := Names[High(Names)];
    if TNameResolver.IsBuiltinTypeName(Bare) or MatchText(Bare, CompilerTypes) or
      Declared.ContainsKey(LowerCase(Bare)) then
      Exit;
    Resolved := Resolver.ResolveChain(AContext.Tree, AContext.RelativePath, Names, ANode.StartOffset);
    // Den Namen selbst markieren, ohne Typargumente.
    Range := TTextRange.Create(ANode.StartPos, TTextPosition.Create(ANode.StartPos.Line,
      ANode.StartPos.Character + Length(ANode.Name)));
    if Resolved.Found then
    begin
      // Gefunden, aber kein Typ: Variable, Konstante, Routine (E2005).
      if (Resolved.Kind in [TResolvedKind.Symbol, TResolvedKind.Local]) and not Resolved.IsType and
        (Resolved.SymbolKind in [TIndexSymbolKind.Constant, TIndexSymbolKind.Variable, TIndexSymbolKind.Field,
        TIndexSymbolKind.Property_, TIndexSymbolKind.Method, TIndexSymbolKind.Routine]) then
        AReport.Add(Range, Format('%s ist kein Typ (wie E2005).', [ANode.Name]), Level);
      Exit;
    end;
    if Resolver.HasUnknownAncestor or Resolver.IsUnitPrefix(ANode.Name) or NestedSomewhere(Bare) then
      Exit;
    Arity := 0;
    Args := ANode.FindChild(TSyntaxKind.GenericArgs);
    if Args <> nil then
      Arity := Args.ChildCount;
    Units := nil;
    if Length(Names) = 1 then
      Units := DeclaringUnits(AContext.Index, Bare, OwnUnit, Arity);
    Message := Format('Typ %s ist nicht deklariert', [ANode.Name]);
    if Length(Units) = 1 then
      Message := Message + Format('; %s fehlt in uses', [Units[0]])
    else if Length(Units) > 1 then
      Message := Message + Format('; in Frage kommen %s', [Alternatives(Units)]);
    // Ziel eines Zeigertyps (PFoo = ^TFoo) meldet der Compiler als undefinierten Typ.
    if (ANode.Parent <> nil) and (ANode.Parent.Kind = TSyntaxKind.PointerType) then
      Message := Message + ' (wie E2564).'
    else
      Message := Message + ' (wie E2003).';
    Fixes := nil;
    for UnitName in Units do
      if TUsesClauses.AddUnit(AContext.Tree.Tokens, ANode.StartOffset, UnitName, LineBreak, Edit) then
      begin
        Fix := TRuleFix.Create(Format('uses %s ergänzen', [UnitName]), [Edit]);
        Fixes := Fixes + [Fix];
      end;
    if Length(Fixes) > 1 then
      for Index := 0 to High(Fixes) do
        Fixes[Index].Alternative := True;
    AReport.Add(Range, Message, Level, Fixes);
  end;

  // Iterativ (Bericht M1).
  procedure Visit(ARoot: TSyntaxNode);
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Index: Integer;
  begin
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Node.Kind in [TSyntaxKind.AsmBlock, TSyntaxKind.WithStatement, TSyntaxKind.Error] then
          Continue;
        if (Node.Kind = TSyntaxKind.TypeReference) and not ((Node.StartPos.Line <= High(Lines)) and
          Lines[Node.StartPos.Line]) then
          CheckReference(Node);
        for Index := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

var
  Token: TPascalToken;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or not TUnresolvedNames.Available(AContext.Index) or
    not TUnresolvedNames.UsesKnown(AContext.Index, TUsesClauses.UsedUnits(AContext.Tree.Tokens),
    AContext.Namespaces, AContext.EnsureUnit) then
    Exit;
  Lines := ConditionalLines(AContext.Tree.Tokens);
  LineBreak := TTextLines.LineBreakOf(AContext.Text);
  OwnUnit := TUsesClauses.OwnName(AContext.Tree.Tokens);
  // Mit Include-Dateien kann der Typ dort deklariert sein.
  Level := TRuleConfidence.High;
  for Token in AContext.Tree.Tokens do
    if (Token.Kind = TPascalTokenKind.Directive) and (StartsText('{$I ', Token.Text) or
      StartsText('{$INCLUDE ', Token.Text)) then
      Level := TRuleConfidence.Medium;
  Declared := TDictionary<string, Boolean>.Create;
  Resolver := TNameResolver.Create(AContext.Index, AContext.EnsureUnit, AContext.TreeUnits);
  try
    Collect(AContext.Tree.Root);
    Resolver.Namespaces := AContext.Namespaces;
    Resolver.PinTree(AContext.Tree, AContext.RelativePath);
    try
      Visit(AContext.Tree.Root);
    finally
      Resolver.UnpinTree;
    end;
  finally
    Resolver.Free;
    Declared.Free;
  end;
end;

procedure RegisterUnresolvedRules(ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TUnresolvedIdentifierRule.Create);
  ARegistry.Register(TUsesUnitNotFoundRule.Create);
  ARegistry.Register(TUnresolvedAttributeRule.Create);
  ARegistry.Register(TUnresolvedTypeRule.Create);
end;

end.
