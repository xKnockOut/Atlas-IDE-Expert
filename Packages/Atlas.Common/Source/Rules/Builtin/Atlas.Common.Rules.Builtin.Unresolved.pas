unit Atlas.Common.Rules.Builtin.Unresolved;

// Nicht auflösbare Bezeichner beim Tippen (#178), wie Compilerfehler E2003,
// aber ohne Compiler (Community Edition, Prüfung in der IDE aus). Nutzt die
// vorsichtige Prüfung aus TUnresolvedNames: nur der erste Name einer Kette in
// Anweisungen, with/asm/anonyme Methoden übersprungen, ohne Unit System im
// Index keine Aussage. Ohne Index (Linter) schweigt die Regel. Alte
// object-Syntax: fehlender Konstruktor in New(P, Init) wie E2601, fehlender
// Destruktor in Dispose(P, Done) wie E2602, Fail außerhalb eines Konstruktors
// wie E2078 (#1382).
//
// uses-unit-not-found (#1016, wie F2613, F1026, F1027, E2202, F2092): Units in
// uses und contains, die der Compiler nicht findet (TRuleContext.Units, die
// Suche steht in Atlas.Common.Projects.UnitLookup), Dateien aus "in '…'",
// Packages aus requires und Units, die sich selbst einbinden. Fehlt die Datei
// aus "in '…'", meldet die Regel das auch ohne Projekt (#1379). Findet die
// Suche nicht einmal System, fehlt der Bibliothekspfad: eine Meldung F1027
// statt einer je Unit. Einträge in {$IF…}-Blöcken bleiben still, ebenso alles, worüber
// die Suche keine sichere Aussage trifft (Installation unbekannt, Makro im
// Pfad). Korrekturen: Namen mit Namespace bzw. ähnlich geschriebene Units
// einsetzen, Ordner außerhalb der Suchpfade in DCC_UnitSearchPath der .dproj
// aufnehmen.
//
// unresolved-attribute (#1019, wie W1074, E2289): Ein Attribut [Name] lässt
// sich weder als Klasse NameAttribute noch als Name auflösen; Delphi warnt nur
// und übergeht es (DUnitX-Tests laufen dann nicht). Nach {$WARN
// UNKNOWN_CUSTOM_ATTRIBUTE ERROR} meldet Delphi 13 E1074 (#1379). Vorgeschlagen wird die Unit,
// die den Typ im Index deklariert; Fassaden-Units, die ihn aus einer anderen
// Kandidaten-Unit weiterreichen (DUnitX.TestFramework), gehen vor. Ohne System
// im Index, wenn eine Unit aus uses nicht im Index steht (sie könnte das
// Attribut deklarieren), in {$IF…}-Blöcken und bei unbekannten Vorfahren bleibt
// die Regel still; Attribute des Compilers (Weak, Unsafe, Ref …) zählen immer.
//
// unresolved-type (#1031, wie E2003, E2564, E2005): Ein Typname in einer
// Deklaration (Feld, Parameter, Ergebnis, Vorfahr, Interface-Liste, Variable,
// Typargument) lässt sich nicht auflösen bzw. bezeichnet keinen Typ. Der Code
// folgt Delphi 13 (#1382): Mitglied hinter einem Punkt (TObject.Create) und
// Variable wie E2005, Routine wie E2007, Konstante wie E2029 (dcc liest sie als
// Anfang eines Teilbereichs und erwartet '..'). Dieselben
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
  Atlas.Common.Rules.Derived,
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
  Atlas.Common.Pascal.DirectiveNames,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.Attributes,
  Atlas.Common.Semantics.SystemIntrinsics,
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
  mCache: IRuleDerivedCache;
  Name: TUnresolvedName;
begin
  if (AContext.Tree = nil) or not TUnresolvedNames.Available(AContext.Index) then
  begin
    Exit;
  end;
  // Resolver des Laufs (TRuleDerived.Resolver); gehört dem Cache.
  mCache := TRuleDerived.Open(AContext);
  Resolver := TRuleDerived.Resolver(mCache, AContext);
  for Name in TUnresolvedNames.Find(Resolver, AContext.Tree, AContext.RelativePath) do
  begin
    if Name.Code <> '' then
    begin
      AReport.Add(Name.Range, TUnresolvedNames.Describe(Name), TRuleConfidence.Medium);
    end
    else if Name.Suggestion <> '' then
    begin
      AReport.Add(Name.Range, Format('"%s" ist nicht deklariert; gemeint ist %s? ({$SCOPEDENUMS ON})',
        [Name.Name, Name.Suggestion]), TRuleConfidence.Medium);
    end
    else
    begin
      AReport.Add(Name.Range, Format('"%s" ist nicht deklariert', [Name.Name]), TRuleConfidence.Medium);
    end;
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
  begin
    Result := Copy(Result, 2, Length(Result) - 2);
  end;
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
  begin
    if IsCode(ATokens[Index]) then
    begin
      IsPackage := SameText(ATokens[Index].Text, 'package');
      Break;
    end;
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
    begin
      Kind := TUsesListKind.UsedUnit;
    end
    else if IsPackage and (ATokens[Index].Kind = TPascalTokenKind.Identifier) and (Previous >= 0) and
      ATokens[Previous].IsSymbol(';') and SameText(ATokens[Index].Text, 'contains') then
    begin
      Kind := TUsesListKind.ContainedUnit;
    end
    else if IsPackage and (ATokens[Index].Kind = TPascalTokenKind.Identifier) and (Previous >= 0) and
      ATokens[Previous].IsSymbol(';') and SameText(ATokens[Index].Text, 'requires') then
    begin
      Kind := TUsesListKind.RequiredPackage;
    end
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
        begin
          Break;
        end;
      end
      else if ATokens[Index].IsKeyword('in') then
      begin
        AfterIn := True;
      end
      else if AfterIn and (ATokens[Index].Kind = TPascalTokenKind.StringLiteral) then
      begin
        InPath := Unquoted(ATokens[Index].Text);
      end
      else if not AfterIn and ((ATokens[Index].Kind = TPascalTokenKind.Identifier) or
        ATokens[Index].IsSymbol('.')) then
      begin
        if First < 0 then
        begin
          First := Index;
        end;
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
      begin
        Continue;
      end;
      if EndsText('.' + AName, Known) then
      begin
        Qualified.Add(Known);
      end
      else
      begin
        Score := TTextFuzzy.EditDistance(AName, Known, MaxDistance);
        if Score <= MaxDistance then
        begin
          Similar.Add(Scored(Score, Known));
        end;
      end;
    end;
    Qualified.Sort;
    Order := TComparer<TScoredName>.Construct(
      function(const ALeft, ARight: TScoredName): Integer
      begin
        Result := ALeft.Score - ARight.Score;
        if Result = 0 then
        begin
          Result := CompareText(ALeft.Name, ARight.Name);
        end;
      end);
    Similar.Sort(Order);
    for Known in Qualified do
    begin
      if Length(Result) < MaxSuggestions then
      begin
        Result := Result + [Known];
      end;
    end;
    for Item in Similar do
    begin
      if Length(Result) < MaxSuggestions then
      begin
        Result := Result + [Item.Name];
      end;
    end;
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
  begin
    if AText[Index] = #10 then
    begin
      Result := TTextPosition.Create(Result.Line + 1, 0);
    end
    else
    begin
      Result := TTextPosition.Create(Result.Line, Result.Character + 1);
    end;
  end;
end;

class function TUsesUnitNotFoundRule.DiffEdit(const AOld, ANew: string): TTextEdit;
var
  Prefix, Suffix: Integer;
begin
  Prefix := 0;
  while (Prefix < Length(AOld)) and (Prefix < Length(ANew)) and (AOld[Prefix + 1] = ANew[Prefix + 1]) do
  begin
    Inc(Prefix);
  end;
  Suffix := 0;
  while (Suffix < Length(AOld) - Prefix) and (Suffix < Length(ANew) - Prefix) and
    (AOld[Length(AOld) - Suffix] = ANew[Length(ANew) - Suffix]) do
  begin
    Inc(Suffix);
  end;
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
    begin
      Result := AItems[Index];
    end
    else if Index = High(AItems) then
    begin
      Result := Result + ' oder ' + AItems[Index];
    end
    else
    begin
      Result := Result + ', ' + AItems[Index];
    end;
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
  begin
    LastLine := Token.EndPos.Line;
  end;
  SetLength(Result, LastLine + 1);
  Depth := 0;
  StartLine := 0;
  for Token in ATokens do
  begin
    if Token.Kind <> TPascalTokenKind.Directive then
    begin
      Continue;
    end;
    Text := UpperCase(Token.Text);
    if StartsStr('{$IF', Text) or StartsStr('(*$IF', Text) then
    begin
      if Depth = 0 then
      begin
        StartLine := Token.StartPos.Line;
      end;
      Inc(Depth);
    end
    else if (Depth > 0) and (StartsStr('{$ENDIF', Text) or StartsStr('{$IFEND', Text) or
      StartsStr('(*$ENDIF', Text) or StartsStr('(*$IFEND', Text)) then
    begin
      Dec(Depth);
      if Depth = 0 then
      begin
        for Line := StartLine to Token.EndPos.Line do
        begin
          Result[Line] := True;
        end;
      end;
    end;
  end;
  if Depth > 0 then
  begin
    for Line := StartLine to LastLine do
    begin
      Result[Line] := True;
    end;
  end;
end;

/// <summary>Quelle der Suche aus der Option searchPaths: project (Vorgabe), atlas oder both.</summary>
function SourcesOf(const AOptions: string): TRuleUnitSources;
var
  Value: string;
begin
  Value := TRuleOptions.Text(AOptions, 'searchPaths', 'project');
  if SameText(Value, 'atlas') then
  begin
    Result := [TRuleUnitSource.Atlas];
  end
  else if SameText(Value, 'both') then
  begin
    Result := [TRuleUnitSource.Project, TRuleUnitSource.Atlas];
  end
  else
  begin
    Result := [TRuleUnitSource.Project];
  end;
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
  begin
    Exit;
  end;
  List := Entries(AContext.Tree.Tokens);
  Lines := ConditionalLines(AContext.Tree.Tokens);
  // F2092: eine Unit, die sich selbst einbindet; braucht keine Pfade.
  Own := TUsesClauses.OwnName(AContext.Tree.Tokens);
  for Entry in List do
  begin
    if (Entry.Kind <> TUsesListKind.RequiredPackage) and (Own <> '') and SameText(Entry.Name, Own) then
    begin
      AReport.Add(Entry.Range, Format('%s verwendet sich selbst (wie F2092).', [Entry.Name]));
    end;
  end;
  if AContext.Units = nil then
  begin
    // F1026 auch ohne Projekt (#1379, Fall CmF1026): "in '…'" gilt nur relativ zur verwendenden Datei, dafür
    // braucht es keine Suchpfade.
    if Assigned(AContext.FileExists) then
    begin
      for Entry in List do
      begin
        if (Entry.Kind <> TUsesListKind.RequiredPackage) and (Entry.InPath <> '') and
          not ((Entry.Range.StartPos.Line <= High(Lines)) and Lines[Entry.Range.StartPos.Line]) and
          not AContext.FileExists(Entry.InPath) then
        begin
          AReport.Add(Entry.Range, Format('Datei %s für %s nicht gefunden (wie F1026).', [Entry.InPath, Entry.Name]));
        end;
      end;
    end;
    Exit;
  end;
  Sources := SourcesOf(AContext.Options);
  // F1027: Ohne System fehlt der Bibliothekspfad; dann eine Meldung statt einer je Unit.
  if AContext.Units.Find('System', '', AContext.FileName, [TRuleUnitSource.Project]) = TRuleUnitAnswer.Missing then
  begin
    if Length(List) > 0 then
    begin
      AReport.Add(List[0].Range, 'Unit System nicht gefunden; der Bibliothekspfad der Installation fehlt ' +
        '(wie F1027).');
    end;
    Exit;
  end;
  HasKnown := False;
  Known := nil;
  for Entry in List do
  begin
    if (Entry.Range.StartPos.Line <= High(Lines)) and Lines[Entry.Range.StartPos.Line] then
    begin
      Continue;
    end;
    if (Own <> '') and SameText(Entry.Name, Own) then
    begin
      Continue;
    end;
    if Entry.Kind = TUsesListKind.RequiredPackage then
    begin
      if AContext.Units.FindPackage(Entry.Name) = TRuleUnitAnswer.Missing then
      begin
        AReport.Add(Entry.Range, Format('Package %s nicht gefunden (wie E2202).', [Entry.Name]));
      end;
      Continue;
    end;
    if AContext.Units.Find(Entry.Name, Entry.InPath, AContext.FileName, Sources) <> TRuleUnitAnswer.Missing then
    begin
      Continue;
    end;
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
    begin
      Fixes := Fixes + [TRuleFix.Create(Format('%s verwenden', [Suggestion]),
        [TTextEdit.Create(Entry.Range, Suggestion)])];
    end;
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
    begin
      for Index := 0 to High(Fixes) do
      begin
        Fixes[Index].Alternative := True;
      end;
    end;
    if Folder <> '' then
    begin
      AReport.Add(Entry.Range, Format('Unit %s nicht gefunden; sie liegt in %s außerhalb der Suchpfade (wie F2613).',
        [Entry.Name, Folder]), TRuleConfidence.High, Fixes);
    end
    else if Length(Suggested) > 0 then
    begin
      AReport.Add(Entry.Range, Format('Unit %s nicht gefunden; ähnlich: %s (wie F2613).',
        [Entry.Name, Alternatives(Suggested)]), TRuleConfidence.High, Fixes);
    end
    else
    begin
      AReport.Add(Entry.Range, Format('Unit %s nicht gefunden (wie F2613).', [Entry.Name]));
    end;
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
  begin
    Exit;
  end;
  Candidates := TList<string>.Create;
  try
    for Name in TAttributes.ClassNames(AName) do
    begin
      for Location in AIndex.FindSymbols(Name) do
      begin
        if (Location.Symbol.Container = '') and (Location.Symbol.Kind in [TIndexSymbolKind.ClassType,
          TIndexSymbolKind.TypeAlias]) and not Candidates.Contains(Location.UnitName) then
        begin
          Candidates.Add(Location.UnitName);
        end;
      end;
    end;
    // Fassade vor Quelle: eine Unit, die eine andere Kandidatin im interface einbindet, reicht den Typ weiter.
    for Name in Candidates do
    begin
      Used := False;
      for Other in Candidates do
      begin
        if not SameText(Other, Name) and AIndex.FindUnit(Other, Found) and
          (IndexText(Name, Found.InterfaceUses) >= 0) then
        begin
          Used := True;
        end;
      end;
      if not Used then
      begin
        Result := Result + [Name];
      end;
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
  begin
    if (Token.StartPos.Line = APosition.Line) and (Token.StartPos.Character = APosition.Character) then
    begin
      Exit(Token.Offset);
    end;
  end;
  Result := 0;
end;

procedure TUnresolvedAttributeRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Resolver: TNameResolver;
  mCache: IRuleDerivedCache;
  Lines: TArray<Boolean>;
  LineBreak: string;
  Level: TRuleConfidence;
  // {$WARN UNKNOWN_CUSTOM_ATTRIBUTE …} außerhalb bedingter Blöcke: Offset und ob ERROR (#1379).
  mSwitchOffsets: TArray<Integer>;
  mSwitchErrors: TArray<Boolean>;

  procedure ReadSwitches;
  var
    mToken: TPascalToken;
    mWords: TArray<string>;
  begin
    mSwitchOffsets := nil;
    mSwitchErrors := nil;
    for mToken in AContext.Tree.Tokens do
    begin
      if (mToken.Kind <> TPascalTokenKind.Directive) or
        ((mToken.StartPos.Line <= High(Lines)) and Lines[mToken.StartPos.Line]) then
      begin
        Continue;
      end;
      mWords := TDirectiveNames.Body(mToken.Text).Split([' ', #9, #13, #10], TStringSplitOptions.ExcludeEmpty);
      if (Length(mWords) >= 3) and SameText(mWords[0], 'WARN') and
        SameText(mWords[1], 'UNKNOWN_CUSTOM_ATTRIBUTE') then
      begin
        mSwitchOffsets := mSwitchOffsets + [mToken.Offset];
        mSwitchErrors := mSwitchErrors + [SameText(mWords[2], 'ERROR')];
      end;
    end;
  end;

  /// <summary>Mit {$WARN UNKNOWN_CUSTOM_ATTRIBUTE ERROR} davor meldet dcc E1074 statt W1074 (#1379).</summary>
  function CodeAt(AOffset: Integer): string;
  var
    mIndex: Integer;
  begin
    Result := 'W1074';
    for mIndex := 0 to High(mSwitchOffsets) do
    begin
      if mSwitchOffsets[mIndex] < AOffset then
      begin
        if mSwitchErrors[mIndex] then
        begin
          Result := 'E1074';
        end
        else
        begin
          Result := 'W1074';
        end;
      end;
    end;
  end;

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
    begin
      NameNode := AItem[0];
    end;
    if not (NameNode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) or
      not TAttributes.At(AContext.Tree, NameNode.StartPos, Use) then
    begin
      Exit;
    end;
    Bare := Copy(Use.Name, LastDelimiter('.', Use.Name) + 1, MaxInt);
    if MatchText(Bare, CompilerAttributes) or MatchText(Bare + 'Attribute', CompilerAttributes) then
    begin
      Exit;
    end;
    // Zuerst NameAttribute, dann Name, wie der Compiler.
    Names := Use.Name.Split(['.']);
    Names[High(Names)] := Names[High(Names)] + 'Attribute';
    Resolved := Resolver.ResolveChain(AContext.Tree, AContext.RelativePath, Names, NameNode.StartOffset);
    if Resolved.Found or Resolver.HasUnknownAncestor then
    begin
      Exit;
    end;
    Resolved := Resolver.ResolveChain(AContext.Tree, AContext.RelativePath, Use.Name.Split(['.']),
      NameNode.StartOffset);
    if Resolved.Found or Resolver.HasUnknownAncestor or Resolver.IsUnitPrefix(Use.Name) then
    begin
      Exit;
    end;
    Units := DeclaringUnits(AContext.Index, Bare);
    if (Length(Units) = 0) and MatchText(Bare, DUnitXAttributes) then
    begin
      Units := [DUnitXUnit];
    end;
    Message := Format('Attribut %s nicht gefunden und wird ignoriert', [Use.Name]);
    if MatchText(Bare, DUnitXAttributes) or ((Length(Units) > 0) and StartsText('DUnitX', Units[0])) then
    begin
      Message := Message + '; die Tests laufen nicht';
    end;
    Message := Message + Format(' (wie %s).', [CodeAt(NameNode.StartOffset)]);
    if Length(Units) = 1 then
    begin
      Message := Message + Format(' Unit %s fehlt.', [Units[0]]);
    end
    else if Length(Units) > 1 then
    begin
      Message := Message + Format(' In Frage kommen %s.', [Alternatives(Units)]);
    end;
    Fixes := nil;
    for UnitName in Units do
    begin
      if TUsesClauses.AddUnit(AContext.Tree.Tokens, OffsetAt(AContext.Tree.Tokens, NameNode.StartPos), UnitName,
        LineBreak, Edit) then
      begin
        Fix := TRuleFix.Create(Format('uses %s ergänzen', [UnitName]), [Edit]);
        Fixes := Fixes + [Fix];
      end;
    end;
    if Length(Fixes) > 1 then
    begin
      for Index := 0 to High(Fixes) do
      begin
        Fixes[Index].Alternative := True;
      end;
    end;
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
          begin
            Continue;
          end;
          for Index := 0 to Node.ChildCount - 1 do
          begin
            CheckItem(Node[Index]);
          end;
          Continue;
        end;
        // In Anweisungen gibt es keine Attribute.
        if Node.Kind in [TSyntaxKind.Block, TSyntaxKind.AsmBlock] then
        begin
          Continue;
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
        end;
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
  begin
    Exit;
  end;
  Lines := ConditionalLines(AContext.Tree.Tokens);
  ReadSwitches;
  LineBreak := TTextLines.LineBreakOf(AContext.Text);
  // Mit Include-Dateien kann das Attribut dort deklariert sein.
  Level := TRuleConfidence.High;
  for Token in AContext.Tree.Tokens do
  begin
    if (Token.Kind = TPascalTokenKind.Directive) and (StartsText('{$I ', Token.Text) or
      StartsText('{$INCLUDE ', Token.Text)) then
    begin
      Level := TRuleConfidence.Medium;
    end;
  end;
  // Resolver des Laufs (TRuleDerived.Resolver); gehört dem Cache.
  mCache := TRuleDerived.Open(AContext);
  Resolver := TRuleDerived.Resolver(mCache, AContext);
  Resolver.PinTree(AContext.Tree, AContext.RelativePath);
  try
    Visit(AContext.Tree.Root);
  finally
    Resolver.UnpinTree;
  end;
end;

{ TUnresolvedTypeRule }

const
  TypeKinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType,
    TIndexSymbolKind.InterfaceType, TIndexSymbolKind.HelperType, TIndexSymbolKind.EnumType,
    TIndexSymbolKind.TypeAlias];

/// <summary>Meldung für einen Namen, der keinen Typ bezeichnet, mit dem Code von Delphi 13 (#1382).</summary>
function NotATypeMessage(const AName: string; AQualified: Boolean; AKind: TIndexSymbolKind): string;
begin
  if AQualified then
  begin
    Result := Format('%s ist kein Typ (wie E2005).', [AName]);
  end
  else if AKind in [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_, TIndexSymbolKind.Routine] then
  begin
    Result := Format('%s ist eine Routine, kein Typ (wie E2007).', [AName]);
  end
  else if AKind in [TIndexSymbolKind.EnumMember, TIndexSymbolKind.Constant] then
  begin
    Result := Format('%s ist eine Konstante, kein Typ; der Compiler liest sie als Anfang eines Teilbereichs ' +
      '%s..Ende (wie E2029).', [AName, AName]);
  end
  else
  begin
    Result := Format('%s ist kein Typ (wie E2005).', [AName]);
  end;
end;

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
  begin
    Exit;
  end;
  Candidates := TList<string>.Create;
  try
    for Location in AIndex.FindSymbols(AName) do
    begin
      if (Location.Symbol.Container <> '') or not (Location.Symbol.Kind in TypeKinds) or
        not Location.Symbol.InInterface or SameText(Location.UnitName, AOwnUnit) or
        Candidates.Contains(Location.UnitName) then
      begin
        Continue;
      end;
      Arity := 0;
      if Location.Symbol.TypeParams <> '' then
      begin
        Arity := Length(Location.Symbol.TypeParams.Split([',']));
      end;
      if Arity = AArity then
      begin
        Candidates.Add(Location.UnitName);
      end;
    end;
    // Fassade vor Quelle wie bei unresolved-attribute.
    for Name in Candidates do
    begin
      Used := False;
      for Other in Candidates do
      begin
        if not SameText(Other, Name) and AIndex.FindUnit(Other, Found) and
          (IndexText(Name, Found.InterfaceUses) >= 0) then
        begin
          Used := True;
        end;
      end;
      if not Used then
      begin
        Result := Result + [Name];
      end;
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
        begin
          Declared.AddOrSetValue(LowerCase(Node.Name), True);
        end
        else if Node.Kind = TSyntaxKind.GenericParams then
        begin
          for Index := 0 to Node.ChildCount - 1 do
          begin
            Declared.AddOrSetValue(LowerCase(Node[Index].Name), True);
          end;
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
        end;
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
    begin
      if (Location.Symbol.Container <> '') and (Location.Symbol.Kind in TypeKinds) then
      begin
        Exit(True);
      end;
    end;
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
    begin
      Exit;
    end;
    Names := ANode.Name.Split(['.']);
    Bare := Names[High(Names)];
    // Typen, die der Compiler kennt, ohne dass System.pas sie deklariert (TextFile, Real48 …, #1382).
    if TResolverText.IsBuiltinTypeName(Bare) or TSystemIntrinsics.IsType(Bare) or
      Declared.ContainsKey(LowerCase(Bare)) then
    begin
      Exit;
    end;
    Resolved := Resolver.ResolveChain(AContext.Tree, AContext.RelativePath, Names, ANode.StartOffset);
    // Den Namen selbst markieren, ohne Typargumente.
    Range := TTextRange.Create(ANode.StartPos, TTextPosition.Create(ANode.StartPos.Line,
      ANode.StartPos.Character + Length(ANode.Name)));
    if Resolved.Found then
    begin
      // Gefunden, aber kein Typ: Variable, Konstante, Routine. Lokale Namen zählen nicht: In hWnd: HWND meint
      // HWND den Typ, der Parametername gilt dort noch nicht (Watchdog, KeyHook).
      if (Resolved.Kind = TResolvedKind.Symbol) and not Resolved.IsType and
        (Resolved.SymbolKind in [TIndexSymbolKind.EnumMember, TIndexSymbolKind.Constant, TIndexSymbolKind.Variable,
        TIndexSymbolKind.Field, TIndexSymbolKind.Property_, TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_,
        TIndexSymbolKind.Routine]) then
      begin
        AReport.Add(Range, NotATypeMessage(ANode.Name, Length(Names) > 1, Resolved.SymbolKind), Level);
      end;
      Exit;
    end;
    if Resolver.HasUnknownAncestor or Resolver.IsUnitPrefix(ANode.Name) or NestedSomewhere(Bare) then
    begin
      Exit;
    end;
    Arity := 0;
    Args := ANode.FindChild(TSyntaxKind.GenericArgs);
    if Args <> nil then
    begin
      Arity := Args.ChildCount;
    end;
    Units := nil;
    if Length(Names) = 1 then
    begin
      Units := DeclaringUnits(AContext.Index, Bare, OwnUnit, Arity);
    end;
    Message := Format('Typ %s ist nicht deklariert', [ANode.Name]);
    if Length(Units) = 1 then
    begin
      Message := Message + Format('; %s fehlt in uses', [Units[0]]);
    end
    else if Length(Units) > 1 then
    begin
      Message := Message + Format('; in Frage kommen %s', [Alternatives(Units)]);
    end;
    // Ziel eines Zeigertyps (PFoo = ^TFoo) meldet der Compiler als undefinierten Typ.
    if (ANode.Parent <> nil) and (ANode.Parent.Kind = TSyntaxKind.PointerType) then
    begin
      Message := Message + ' (wie E2564).';
    end
    else
    begin
      Message := Message + ' (wie E2003).';
    end;
    Fixes := nil;
    for UnitName in Units do
    begin
      if TUsesClauses.AddUnit(AContext.Tree.Tokens, ANode.StartOffset, UnitName, LineBreak, Edit) then
      begin
        Fix := TRuleFix.Create(Format('uses %s ergänzen', [UnitName]), [Edit]);
        Fixes := Fixes + [Fix];
      end;
    end;
    if Length(Fixes) > 1 then
    begin
      for Index := 0 to High(Fixes) do
      begin
        Fixes[Index].Alternative := True;
      end;
    end;
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
        begin
          Continue;
        end;
        if (Node.Kind = TSyntaxKind.TypeReference) and not ((Node.StartPos.Line <= High(Lines)) and
          Lines[Node.StartPos.Line]) then
        begin
          CheckReference(Node);
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
        end;
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
  begin
    Exit;
  end;
  Lines := ConditionalLines(AContext.Tree.Tokens);
  LineBreak := TTextLines.LineBreakOf(AContext.Text);
  OwnUnit := TUsesClauses.OwnName(AContext.Tree.Tokens);
  // Mit Include-Dateien kann der Typ dort deklariert sein.
  Level := TRuleConfidence.High;
  for Token in AContext.Tree.Tokens do
  begin
    if (Token.Kind = TPascalTokenKind.Directive) and (StartsText('{$I ', Token.Text) or
      StartsText('{$INCLUDE ', Token.Text)) then
    begin
      Level := TRuleConfidence.Medium;
    end;
  end;
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
