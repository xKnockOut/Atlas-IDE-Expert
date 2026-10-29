unit Atlas.Common.Rules.Builtin.Units;

// Regeln für Unit-Kopf, uses und Dateiende (#909, Gruppe Compiler vorab):
//   unit-name-mismatch  Der Name hinter unit weicht vom Dateinamen ab (#990,
//                       wie E1038, W1038), oder die Datei aus "uses X in
//                       '…'" deklariert eine andere Unit als X (wie E2085).
//                       Passt dort auch der Name der Unit nicht zu ihrer
//                       Datei, meldet Delphi 13 nur E1038 in der Unit
//                       (#1382); dann schweigt die Regel in der uses-Klausel.
//   text-after-final-end  Code nach dem abschließenden end. (#991, wie W1011);
//                       Kommentare und Direktiven nur mit allowComments =
//                       false.
//   exports-invalid     exports in einer Routine (#1077, wie E2191), Export
//                       einer threadvar oder einer Routine mit local (wie
//                       E2276), einer Variablen, Konstanten oder eines Typs
//                       (wie E2121) und derselbe Eintrag bzw. Exportname
//                       zweimal (wie E2287).
//   unit-name-conflict  Eine Unit heißt System oder SysInit (#1079, wie
//                       E2272), oder {$NOINCLUDE X} nennt eine Unit, die die
//                       Unit-Suche sicher nicht findet (wie E2242).
//   implicit-variants-unit  Variant oder OleVariant als Typ ohne System.Variants
//                       in uses (#1082, wie W1040); experimentell, also nur
//                       eingeschaltet aktiv.
//
// Die Regeln lesen nur den Text der Datei und, für "in '…'", die genannte
// Datei über TRuleContext.ReadFile. Ohne Dateinamen, ohne lesbare Datei und
// für Einträge in {$IF…}-Zweigen schweigen sie. text-after-final-end sucht
// das abschließende end. hinter dem letzten Abschnitt des Syntaxbaums und
// schweigt, wenn der Parser Fehler meldet oder end. in einem {$IF…}-Zweig
// steht. exports-invalid löst Namen nur gegen globale Deklarationen der
// Datei auf; Namen aus anderen Units und Namen mit Punkt bleiben still,
// ebenso zwei Einträge in sich ausschließenden {$IF…}-Zweigen.
// unit-name-conflict schweigt in den Quellen der RTL (source/rtl), wo System
// und SysInit zu Hause sind. Die Codes E2399, E2447, W1051 und X2421 aus #1079
// meldet sie nicht: E2447, W1051 und X2421 gehören zu den Namensräumen der
// .NET-Metadaten, die dcc32/dcc64 nicht erzeugt; für E2399 nennt die
// docwiki keine Bedingung, und eine Unit Kunden neben Kunden.Daten übersetzt
// Delphi ohne Fehler (Spring.pas neben Spring.Collections.pas, Atlas selbst).
// implicit-variants-unit zählt Typangaben im Syntaxbaum (Variablen, Felder,
// Parameter, Ergebnisse, Typargumente); Variants im uses gilt auch in einem
// {$IF…}-Zweig und ohne Namespace. Schweigt in System, SysInit und Variants
// selbst, wenn die Datei einen eigenen Typ Variant deklariert und nach
// {$WARN IMPLICIT_VARIANTS OFF}. {$WARN UNIT_NAME_MISMATCH
// OFF} und {$WARNINGS OFF} vor dem Unit-Namen schalten W1038 wie beim
// Compiler ab.

interface

uses
  System.SysUtils,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  UnitNameMismatchRuleId = 'unit-name-mismatch';
  TextAfterFinalEndRuleId = 'text-after-final-end';
  ExportsInvalidRuleId = 'exports-invalid';
  UnitNameConflictRuleId = 'unit-name-conflict';
  ImplicitVariantsUnitRuleId = 'implicit-variants-unit';

type
{$SCOPEDENUMS ON}
  /// <summary>Art einer Quelltextdatei nach ihrem ersten Wort.</summary>
  TModuleKind = (None, UnitModule, ProgramModule, LibraryModule, PackageModule);
{$SCOPEDENUMS OFF}

  /// <summary>Kopf einer Quelltextdatei: unit, program, library oder package mit Namen.</summary>
  TModuleHeader = record
    Kind: TModuleKind;
    /// <summary>Name wie geschrieben, mit Punkten; '' ohne Namen.</summary>
    Name: string;
    /// <summary>Token-Index des ersten und letzten Namensteils; -1 ohne Namen.</summary>
    First: Integer;
    Last: Integer;
    /// <summary>Liest den Kopf aus den Token; Kind None, wenn die Datei nicht so beginnt.</summary>
    class function Read(const ATokens: TArray<TPascalToken>): TModuleHeader; static;
  end;

  TUnitNameMismatchRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Unit-Name, den der Compiler für ein Dateiname erwartet (ohne Ordner und .pas); '' für andere
    /// Endungen oder ohne Namen.</summary>
    class function ExpectedName(const APath: string): string; static;
  end;

  TTextAfterFinalEndRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Token-Index des Punkts im abschließenden end. bzw. im end. des Programms; -1, wenn der Baum ihn
    /// nicht sicher bestimmt.</summary>
    class function FinalDot(const AContext: TRuleContext): Integer; static;
  end;

  /// <summary>Ein Eintrag einer exports-Klausel (#1077).</summary>
  TExportEntry = record
    /// <summary>Name wie geschrieben, mit Punkten.</summary>
    Name: string;
    /// <summary>Parameterliste ohne Leerraum in Großbuchstaben; '' ohne.</summary>
    Parameters: string;
    /// <summary>Text aus name '…', wenn er ein einzelnes String-Literal ist; sonst ''.</summary>
    ExportName: string;
    /// <summary>Es gibt eine name-Klausel (auch mit Ausdruck).</summary>
    HasNameClause: Boolean;
    /// <summary>Token-Index des ersten und letzten Tokens des Eintrags und des Namens.</summary>
    First: Integer;
    Last: Integer;
    NameLast: Integer;
  end;

  TExportsInvalidRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Einträge der Klausel zwischen den Token-Indizes AFirst (exports) und ALast (Semikolon).</summary>
    class function Entries(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer): TArray<TExportEntry>;
      static;
  end;

  TUnitNameConflictRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TImplicitVariantsUnitRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

/// <summary>Ist die Warnung AName ({$WARN AName …}) an AOffset eingeschaltet? Wertet {$WARN AName ON|OFF|ERROR|
/// DEFAULT} und {$WARNINGS ON|OFF} davor aus, wie der Compiler in Textreihenfolge.</summary>
function WarningEnabled(const ATokens: TArray<TPascalToken>; const AName: string; AOffset: Integer): Boolean;

/// <summary>Text der Datei AFileName neben der geprüften Unit über TRuleContext.ReadFile; False ohne.</summary>
function ReadNeighbour(const AContext: TRuleContext; const AFileName: string; out AText: string): Boolean;

procedure RegisterUnitRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.ConditionalBranches,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Rules.Options,
  Atlas.Common.Editing.UsesClause,
  Atlas.Text.Lines,
  Atlas.Common.Pascal.DirectiveNames,
  Atlas.Common.Rules.Builtin.Unresolved;

function IsCode(const AToken: TPascalToken): Boolean;
begin
  Result := not (AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]);
end;

function RangeOf(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer): TTextRange;
begin
  Result := TTextRange.Create(ATokens[AFirst].StartPos, ATokens[ALast].EndPos);
end;

/// <summary>Ist AText ein Name aus Bezeichnern mit Punkten dazwischen?</summary>
function IsQualifiedName(const AText: string): Boolean;
var
  Part: string;
begin
  Result := AText <> '';
  if Result then
    for Part in AText.Split(['.']) do
      if not IsValidIdent(Part) then
        Exit(False);
end;

/// <summary>Steht das Token an APosition in einem {$IF…}-Zweig?</summary>
function InBranch(const ATokens: TArray<TPascalToken>; const APaths: TArray<string>;
  const APosition: TTextPosition): Boolean;
var
  Index: Integer;
begin
  Result := False;
  if APaths = nil then
    Exit;
  for Index := 0 to High(ATokens) do
    if (ATokens[Index].StartPos.Line = APosition.Line) and
      (ATokens[Index].StartPos.Character = APosition.Character) then
      Exit(TConditionalBranches.PathAt(APaths, Index) <> '');
end;

{ TModuleHeader }

class function TModuleHeader.Read(const ATokens: TArray<TPascalToken>): TModuleHeader;
var
  Index: Integer;
begin
  Result.Kind := TModuleKind.None;
  Result.Name := '';
  Result.First := -1;
  Result.Last := -1;
  Index := 0;
  while (Index <= High(ATokens)) and not IsCode(ATokens[Index]) do
    Inc(Index);
  if Index > High(ATokens) then
    Exit;
  if ATokens[Index].IsKeyword('unit') then
    Result.Kind := TModuleKind.UnitModule
  else if ATokens[Index].IsKeyword('program') then
    Result.Kind := TModuleKind.ProgramModule
  else if ATokens[Index].IsKeyword('library') then
    Result.Kind := TModuleKind.LibraryModule
  else if (ATokens[Index].Kind = TPascalTokenKind.Identifier) and SameText(ATokens[Index].Text, 'package') then
    Result.Kind := TModuleKind.PackageModule
  else
    Exit;
  Inc(Index);
  while Index <= High(ATokens) do
  begin
    if not IsCode(ATokens[Index]) then
    begin
      Inc(Index);
      Continue;
    end;
    // Ein Namensteil am Anfang oder nach einem Punkt; danach folgen nur noch Hinweise wie platform.
    if ((Result.Name = '') and (ATokens[Index].Kind = TPascalTokenKind.Identifier)) or
      ((Result.Name <> '') and (Result.Name[Length(Result.Name)] = '.') and
      (ATokens[Index].Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword])) then
    begin
      if Result.First < 0 then
        Result.First := Index;
      Result.Last := Index;
      Result.Name := Result.Name + ATokens[Index].Text;
    end
    else if ATokens[Index].IsSymbol('.') and (Result.Name <> '') then
      Result.Name := Result.Name + '.'
    else
      Break;
    Inc(Index);
  end;
  // Ein Punkt am Ende gehört nicht zum Namen (halb getippt).
  if EndsStr('.', Result.Name) then
    Result.Name := Copy(Result.Name, 1, Length(Result.Name) - 1);
end;

{ Hilfen }

function WarningEnabled(const ATokens: TArray<TPascalToken>; const AName: string; AOffset: Integer): Boolean;
var
  Token: TPascalToken;
  Name, Body, Rest: string;
begin
  Result := True;
  for Token in ATokens do
  begin
    if Token.Offset >= AOffset then
      Break;
    if Token.Kind <> TPascalTokenKind.Directive then
      Continue;
    Name := TPascalLexer.DirectiveName(Token.Text);
    Body := TDirectiveNames.Body(Token.Text);
    Rest := UpperCase(Trim(Copy(Body, Length(TDirectiveNames.LeadingName(Body)) + 1, MaxInt)));
    if Name = 'WARNINGS' then
      Result := Rest <> 'OFF'
    else if (Name = 'WARN') and SameText(TDirectiveNames.LeadingName(Rest), AName) then
      Result := not EndsStr(' OFF', Rest);
  end;
end;

function ReadNeighbour(const AContext: TRuleContext; const AFileName: string; out AText: string): Boolean;
var
  Bytes: TBytes;
  Format: TFileFormat;
begin
  AText := '';
  Result := (AFileName <> '') and Assigned(AContext.ReadFile) and AContext.ReadFile(AFileName, Bytes);
  if Result then
    AText := TFileEncoding.Decode(Bytes, Format);
end;

{ TUnitNameMismatchRule }

function TUnitNameMismatchRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(UnitNameMismatchRuleId, TRuleSeverity.Error,
    'Unit-Name passt nicht zum Dateinamen (wie E1038)');
end;

class function TUnitNameMismatchRule.ExpectedName(const APath: string): string;
var
  Name: string;
begin
  Name := StringReplace(APath, '\', '/', [rfReplaceAll]);
  Name := Copy(Name, LastDelimiter('/', Name) + 1, MaxInt);
  if not EndsText('.pas', Name) then
    Exit('');
  Result := Copy(Name, 1, Length(Name) - Length('.pas'));
end;

procedure TUnitNameMismatchRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Paths: TArray<string>;
  Header, Used: TModuleHeader;
  Expected, Path, Text: string;
  Entry: TUsesListEntry;
  Fixes: TArray<TRuleFix>;
  Range: TTextRange;
begin
  if AContext.Tree = nil then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Header := TModuleHeader.Read(Tokens);
  // Kopf der Unit gegen den Dateinamen.
  Path := AContext.FileName;
  if Path = '' then
    Path := AContext.RelativePath;
  Expected := ExpectedName(Path);
  if (Header.Kind = TModuleKind.UnitModule) and (Header.Name <> '') and (Expected <> '') and
    not SameText(Header.Name, Expected) and WarningEnabled(Tokens, 'UNIT_NAME_MISMATCH', Tokens[Header.First].Offset)
  then
  begin
    Range := RangeOf(Tokens, Header.First, Header.Last);
    Fixes := nil;
    if IsQualifiedName(Expected) then
      Fixes := [TRuleFix.Create(Format('Unit-Namen in %s ändern', [Expected]), [TRuleEdit.Create(Range, Expected)])];
    AReport.Add(Range, Format('Unit-Name %s passt nicht zur Datei %s.pas (wie E1038).', [Header.Name, Expected]),
      TRuleConfidence.High, Fixes);
  end;
  // uses X in '…': Die Datei muss die Unit X deklarieren.
  Paths := TConditionalBranches.Paths(Tokens);
  for Entry in TUsesUnitNotFoundRule.Entries(Tokens) do
  begin
    if (Entry.Kind = TUsesListKind.RequiredPackage) or (Entry.InPath = '') or
      not ReadNeighbour(AContext, Entry.InPath, Text) then
      Continue;
    if InBranch(Tokens, Paths, Entry.Range.StartPos) then
      Continue;
    Used := TModuleHeader.Read(TPascalLexer.Tokenize(Text));
    if (Used.Kind <> TModuleKind.UnitModule) or (Used.Name = '') or SameText(Used.Name, Entry.Name) then
      Continue;
    // Ursache in der Unit selbst: Dort meldet dcc E1038 (bzw. diese Regel, wenn die Datei geprüft wird).
    if (ExpectedName(Entry.InPath) <> '') and not SameText(Used.Name, ExpectedName(Entry.InPath)) then
      Continue;
    AReport.Add(Entry.Range, Format('%s in ''%s'': die Datei deklariert die Unit %s (wie E2085).',
      [Entry.Name, Entry.InPath, Used.Name]), TRuleConfidence.High,
      [TRuleFix.Create(Format('In %s ändern', [Used.Name]), [TRuleEdit.Create(Entry.Range, Used.Name)])]);
  end;
end;

{ TTextAfterFinalEndRule }

function TTextAfterFinalEndRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(TextAfterFinalEndRuleId, TRuleSeverity.Warning,
    'Text nach dem abschließenden end. (wie W1011)');
end;

class function TTextAfterFinalEndRule.FinalDot(const AContext: TRuleContext): Integer;
var
  Tokens: TArray<TPascalToken>;
  Root: TSyntaxNode;
  From, Index: Integer;
begin
  Result := -1;
  if (AContext.Tree = nil) or (AContext.Tree.Diagnostics <> nil) or (AContext.Tree.Root = nil) or
    (AContext.Tree.Root.ChildCount = 0) then
    Exit;
  Root := AContext.Tree.Root;
  Tokens := AContext.Tree.Tokens;
  // Hinter dem letzten Abschnitt folgen end und der Punkt; beim Programm gehört end zum Block.
  From := Root.Children[Root.ChildCount - 1].EndOffset;
  Index := 0;
  while (Index <= High(Tokens)) and (Tokens[Index].Offset < From) do
    Inc(Index);
  while (Index <= High(Tokens)) and not IsCode(Tokens[Index]) do
    Inc(Index);
  if (Index <= High(Tokens)) and Tokens[Index].IsKeyword('end') then
  begin
    Inc(Index);
    while (Index <= High(Tokens)) and not IsCode(Tokens[Index]) do
      Inc(Index);
  end;
  if (Index <= High(Tokens)) and Tokens[Index].IsSymbol('.') then
    Result := Index;
end;

procedure TTextAfterFinalEndRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Dot, First, Index: Integer;
  AllowComments: Boolean;
  Message: string;
begin
  Dot := FinalDot(AContext);
  if Dot < 0 then
    Exit;
  Tokens := AContext.Tree.Tokens;
  if TConditionalBranches.PathAt(TConditionalBranches.Paths(Tokens), Dot) <> '' then
    Exit;
  if not WarningEnabled(Tokens, '', Tokens[Dot].Offset) then
    Exit;
  AllowComments := TRuleOptions.Bool(AContext.Options, 'allowComments', True);
  First := -1;
  for Index := Dot + 1 to High(Tokens) do
    if IsCode(Tokens[Index]) or not AllowComments then
    begin
      First := Index;
      Break;
    end;
  if First < 0 then
    Exit;
  Message := 'Kommentar nach end. wird nicht übersetzt (wie W1011).';
  for Index := First to High(Tokens) do
    if IsCode(Tokens[Index]) then
      Message := 'Code nach end. wird nicht übersetzt (wie W1011).';
  // Entfernt wird ab dem Ende des Tokens davor, damit keine Leerzeilen stehen bleiben.
  AReport.Add(RangeOf(Tokens, First, High(Tokens)), Message, TRuleConfidence.High,
    [TRuleFix.Create('Text nach end. entfernen',
    [TRuleEdit.Create(TTextRange.Create(Tokens[First - 1].EndPos, Tokens[High(Tokens)].EndPos), '')])]);
end;

{ TExportsInvalidRule }

function TExportsInvalidRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(ExportsInvalidRuleId, TRuleSeverity.Error,
    'exports-Klausel unzulässig (wie E2191, E2276, E2121, E2287)');
end;

/// <summary>Text eines String-Literals ohne Hochkommas ('' wird ').</summary>
function Unquoted(const AText: string): string;
begin
  Result := AText;
  if (Length(Result) >= 2) and (Result[1] = '''') and (Result[Length(Result)] = '''') then
    Result := Copy(Result, 2, Length(Result) - 2);
  Result := StringReplace(Result, '''''', '''', [rfReplaceAll]);
end;

class function TExportsInvalidRule.Entries(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer):
  TArray<TExportEntry>;
var
  Index, Depth, Literals: Integer;
  Entry: TExportEntry;
  InName, InParams, AfterName: Boolean;

  procedure Finish;
  begin
    if Entry.Name <> '' then
      Result := Result + [Entry];
    Entry := Default(TExportEntry);
    Entry.First := -1;
    InName := False;
    InParams := False;
    AfterName := False;
    Literals := 0;
  end;

begin
  Result := nil;
  Depth := 0;
  Finish;
  for Index := AFirst + 1 to ALast do
  begin
    if not IsCode(ATokens[Index]) then
      Continue;
    if (Depth = 0) and (ATokens[Index].IsSymbol(',') or ATokens[Index].IsSymbol(';')) then
    begin
      if Entry.HasNameClause and (Literals <> 1) then
        Entry.ExportName := '';
      Finish;
      Continue;
    end;
    if Entry.First < 0 then
      Entry.First := Index;
    Entry.Last := Index;
    if ATokens[Index].IsSymbol('(') then
    begin
      Inc(Depth);
      if (Depth = 1) and not AfterName then
        InParams := True;
    end
    else if ATokens[Index].IsSymbol(')') then
      Dec(Depth);
    if InParams then
    begin
      Entry.Parameters := Entry.Parameters + UpperCase(ATokens[Index].Text);
      if Depth = 0 then
      begin
        InParams := False;
        AfterName := True;
      end;
    end
    else if not AfterName and (((Entry.Name = '') and (ATokens[Index].Kind = TPascalTokenKind.Identifier)) or
      (EndsStr('.', Entry.Name) and (ATokens[Index].Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword])) or
      ((Entry.Name <> '') and not EndsStr('.', Entry.Name) and ATokens[Index].IsSymbol('.'))) then
    begin
      Entry.Name := Entry.Name + ATokens[Index].Text;
      Entry.NameLast := Index;
    end
    else
    begin
      AfterName := True;
      if (Depth = 0) and (ATokens[Index].Kind = TPascalTokenKind.Identifier) and
        MatchText(ATokens[Index].Text, ['name', 'index', 'resident']) then
      begin
        InName := SameText(ATokens[Index].Text, 'name');
        if InName then
        begin
          Entry.HasNameClause := True;
          Literals := 0;
        end;
      end
      else if InName then
      begin
        if (ATokens[Index].Kind = TPascalTokenKind.StringLiteral) and (Literals = 0) then
          Entry.ExportName := Unquoted(ATokens[Index].Text);
        Inc(Literals);
      end;
    end;
  end;
  // Ohne Semikolon am Ende (halb getippt) zählt der letzte Eintrag nicht.
end;

type
{$SCOPEDENUMS ON}
  TGlobalKind = (Routine, LocalRoutine, ThreadVariable, Variable, Constant, TypeName);
{$SCOPEDENUMS OFF}
  TGlobalKinds = set of TGlobalKind;

/// <summary>Arten der globalen Deklarationen der Datei je Name in Großbuchstaben.</summary>
function GlobalKinds(ARoot: TSyntaxNode; const AName: string): TGlobalKinds;
var
  Found: TGlobalKinds;

  // Rekursion nur in interface- und implementation-Abschnitt (höchstens zwei Ebenen, unabhängig von der
  // Ausdruckstiefe).
  procedure Visit(ANode: TSyntaxNode);
  var
    Index, Inner: Integer;
    Child, Header: TSyntaxNode;
    Name: string;
    IsLocal: Boolean;
  begin
    for Index := 0 to ANode.ChildCount - 1 do
    begin
      Child := ANode.Children[Index];
      case Child.Kind of
        TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection:
          Visit(Child);
        TSyntaxKind.RoutineDecl:
          if SameText(Child.Name, AName) then
          begin
            Header := Child.FindChild(TSyntaxKind.RoutineHeader);
            IsLocal := False;
            if Header <> nil then
              for Inner := 0 to Header.ChildCount - 1 do
                if (Header.Children[Inner].Kind = TSyntaxKind.Directive) and (Header.Children[Inner].Name = 'local') then
                  IsLocal := True;
            if IsLocal then
              Include(Found, TGlobalKind.LocalRoutine)
            else
              Include(Found, TGlobalKind.Routine);
          end;
        TSyntaxKind.VarSection:
          for Inner := 0 to Child.ChildCount - 1 do
            if Child.Children[Inner].Kind = TSyntaxKind.VarDecl then
              for Name in Child.Children[Inner].Name.Split([',']) do
                if SameText(Trim(Name), AName) then
                  if Child.Name = 'threadvar' then
                    Include(Found, TGlobalKind.ThreadVariable)
                  else
                    Include(Found, TGlobalKind.Variable);
        TSyntaxKind.ConstSection:
          for Inner := 0 to Child.ChildCount - 1 do
            if (Child.Children[Inner].Kind = TSyntaxKind.ConstDecl) and SameText(Child.Children[Inner].Name, AName) then
              Include(Found, TGlobalKind.Constant);
        TSyntaxKind.TypeSection:
          for Inner := 0 to Child.ChildCount - 1 do
            if (Child.Children[Inner].Kind = TSyntaxKind.TypeDecl) and SameText(Child.Children[Inner].Name, AName) then
              Include(Found, TGlobalKind.TypeName);
      else
        // Übrige Werte bewusst ohne Wirkung.
      end;
    end;
  end;

begin
  Found := [];
  Visit(ARoot);
  Result := Found;
end;

/// <summary>Steht ANode in einer Routine?</summary>
function InRoutine(ANode: TSyntaxNode): Boolean;
var
  Parent: TSyntaxNode;
begin
  Parent := ANode.Parent;
  while Parent <> nil do
  begin
    if Parent.Kind = TSyntaxKind.RoutineDecl then
      Exit(True);
    Parent := Parent.Parent;
  end;
  Result := False;
end;

procedure TExportsInvalidRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
type
  TClause = record
    First: Integer;
    Last: Integer;
    Entries: TArray<TExportEntry>;
  end;
var
  Tokens: TArray<TPascalToken>;
  Paths: TArray<string>;
  Clauses: TArray<TClause>;
  Clause: TClause;
  Nodes: TArray<TSyntaxNode>;
  Node: TSyntaxNode;
  ClauseIndex, EntryIndex, Other, OtherEntry: Integer;
  Entry, Earlier: TExportEntry;
  Kinds: TGlobalKinds;
  Duplicate: Boolean;
  Message: string;

  function TokenIndexAt(AOffset: Integer): Integer;
  begin
    Result := 0;
    while (Result <= High(Tokens)) and (Tokens[Result].Offset < AOffset) do
      Inc(Result);
  end;

  /// <summary>Entfernt den Eintrag AEntry aus AClause samt Komma; als einziger Eintrag die ganze Klausel.</summary>
  function RemoveFix(const AClause: TClause; AEntry: Integer): TRuleFix;
  var
    Range: TTextRange;
  begin
    if Length(AClause.Entries) = 1 then
      Range := RangeOf(Tokens, AClause.First, AClause.Last)
    else if AEntry > 0 then
      Range := TTextRange.Create(Tokens[AClause.Entries[AEntry - 1].Last].EndPos,
        Tokens[AClause.Entries[AEntry].Last].EndPos)
    else
      Range := TTextRange.Create(Tokens[AClause.Entries[0].First].StartPos, Tokens[AClause.Entries[1].First].StartPos);
    Result := TRuleFix.Create('Doppelten Eintrag entfernen', [TRuleEdit.Create(Range, '')]);
  end;

  function Exclusive(AFirst, ASecond: Integer): Boolean;
  begin
    Result := TConditionalBranches.Exclusive(TConditionalBranches.PathAt(Paths, AFirst),
      TConditionalBranches.PathAt(Paths, ASecond));
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Nodes := nil;
  AContext.Tree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      if ANode.Kind = TSyntaxKind.ExportsClause then
        Nodes := Nodes + [ANode];
      Result := True;
    end);
  if Nodes = nil then
    Exit;
  Paths := TConditionalBranches.Paths(Tokens);
  Clauses := nil;
  for Node in Nodes do
  begin
    Clause.First := TokenIndexAt(Node.StartOffset);
    Clause.Last := TokenIndexAt(Node.EndOffset) - 1;
    if (Clause.First > High(Tokens)) or not Tokens[Clause.First].IsKeyword('exports') or
      not Tokens[Clause.Last].IsSymbol(';') then
      Continue;
    if InRoutine(Node) then
    begin
      AReport.Add(RangeOf(Tokens, Clause.First, Clause.First),
        'exports ist nur auf globaler Ebene erlaubt (wie E2191).', TRuleConfidence.High);
      Continue;
    end;
    Clause.Entries := Entries(Tokens, Clause.First, Clause.Last);
    Clauses := Clauses + [Clause];
  end;
  for ClauseIndex := 0 to High(Clauses) do
    for EntryIndex := 0 to High(Clauses[ClauseIndex].Entries) do
    begin
      Entry := Clauses[ClauseIndex].Entries[EntryIndex];
      // Was der Name meint, steht nur für Namen ohne Punkt sicher fest, die die Datei global deklariert.
      Message := '';
      if Pos('.', Entry.Name) = 0 then
      begin
        Kinds := GlobalKinds(AContext.Tree.Root, Entry.Name);
        if TGlobalKind.Routine in Kinds then
          Message := ''
        else if TGlobalKind.LocalRoutine in Kinds then
          Message := Format('%s ist mit local deklariert und kann nicht exportiert werden (wie E2276).', [Entry.Name])
        else if TGlobalKind.ThreadVariable in Kinds then
          Message := Format('Die threadvar %s kann nicht exportiert werden (wie E2276).', [Entry.Name])
        else if Kinds <> [] then
          Message := Format('%s ist keine Prozedur oder Funktion und kann nicht exportiert werden (wie E2121).',
            [Entry.Name]);
      end;
      if Message <> '' then
        AReport.Add(RangeOf(Tokens, Entry.First, Entry.NameLast), Message, TRuleConfidence.High);
      // Derselbe Eintrag oder derselbe Exportname weiter vorn.
      Duplicate := False;
      for Other := 0 to ClauseIndex do
      begin
        for OtherEntry := 0 to High(Clauses[Other].Entries) do
        begin
          if (Other = ClauseIndex) and (OtherEntry >= EntryIndex) then
            Break;
          Earlier := Clauses[Other].Entries[OtherEntry];
          if Exclusive(Earlier.First, Entry.First) then
            Continue;
          if not Entry.HasNameClause and not Earlier.HasNameClause and SameText(Entry.Name, Earlier.Name) and
            (Entry.Parameters = Earlier.Parameters) then
            Message := Format('%s wird zweimal exportiert (wie E2287).', [Entry.Name])
          else if (Entry.ExportName <> '') and (Entry.ExportName = Earlier.ExportName) then
            Message := Format('Der Name ''%s'' wird zweimal exportiert (wie E2287).', [Entry.ExportName])
          else
            Continue;
          Duplicate := True;
          Break;
        end;
        if Duplicate then
          Break;
      end;
      if Duplicate then
        AReport.Add(RangeOf(Tokens, Entry.First, Entry.Last), Message, TRuleConfidence.High,
          [RemoveFix(Clauses[ClauseIndex], EntryIndex)]);
    end;
end;

{ TUnitNameConflictRule }

function TUnitNameConflictRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(UnitNameConflictRuleId, TRuleSeverity.Error,
    'Unit-Name kollidiert (wie E2272, E2242)');
end;

procedure TUnitNameConflictRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Header: TModuleHeader;
  Path, Body, Name, Suggestion: string;
  Token: TPascalToken;
  At: Integer;
  Range: TTextRange;
  Fixes: TArray<TRuleFix>;
begin
  if AContext.Tree = nil then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Header := TModuleHeader.Read(Tokens);
  Path := StringReplace(AContext.FileName + '|' + AContext.RelativePath, '\', '/', [rfReplaceAll]);
  if (Header.Kind = TModuleKind.UnitModule) and MatchText(Header.Name, ['System', 'SysInit']) and
    not ContainsText(Path, 'source/rtl/') then
    AReport.Add(RangeOf(Tokens, Header.First, Header.Last), Format('Der Unit-Name %s ist für den Compiler ' +
      'reserviert (wie E2272).', [Header.Name]), TRuleConfidence.High);
  // {$NOINCLUDE X} braucht eine Unit, die der Compiler kennt.
  if AContext.Units = nil then
    Exit;
  for Token in Tokens do
  begin
    if (Token.Kind <> TPascalTokenKind.Directive) or (TPascalLexer.DirectiveName(Token.Text) <> 'NOINCLUDE') then
      Continue;
    Body := TDirectiveNames.Body(Token.Text);
    Name := Trim(Copy(Body, Length(TDirectiveNames.LeadingName(Body)) + 1, MaxInt));
    if not IsQualifiedName(Name) or (Token.StartPos.Line <> Token.EndPos.Line) then
      Continue;
    if AContext.Units.Find(Name, '', AContext.FileName, [TRuleUnitSource.Project]) <> TRuleUnitAnswer.Missing then
      Continue;
    At := Pos(Name, Token.Text);
    Range := TTextRange.Create(Token.StartPos.Line, Token.StartPos.Character + At - 1, Token.StartPos.Line,
      Token.StartPos.Character + At - 1 + Length(Name));
    Fixes := nil;
    for Suggestion in TUsesUnitNotFoundRule.Suggestions(Name, AContext.Units.KnownUnits([TRuleUnitSource.Project])) do
      Fixes := Fixes + [TRuleFix.Create(Format('%s verwenden', [Suggestion]), [TRuleEdit.Create(Range, Suggestion)])];
    AReport.Add(Range, Format('{$NOINCLUDE %s}: %s ist keine bekannte Unit (wie E2242).', [Name, Name]),
      TRuleConfidence.High, Fixes);
  end;
end;

{ TImplicitVariantsUnitRule }

function TImplicitVariantsUnitRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(ImplicitVariantsUnitRuleId, TRuleSeverity.Hint,
    'Variant ohne System.Variants in uses (wie W1040)', True);
end;

procedure TImplicitVariantsUnitRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Header: TModuleHeader;
  Used: TArray<string>;
  Name, UnitName: string;
  First: TSyntaxNode;
  OwnType: Boolean;
  Edit: TTextEdit;
  Fixes: TArray<TRuleFix>;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Header := TModuleHeader.Read(Tokens);
  if MatchText(Header.Name, ['System', 'SysInit', 'System.Variants', 'Variants']) then
    Exit;
  Used := TUsesClauses.UsedUnits(Tokens);
  for Name in Used do
    if MatchText(Name, ['System.Variants', 'Variants']) then
      Exit;
  First := nil;
  OwnType := False;
  AContext.Tree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      if (ANode.Kind = TSyntaxKind.TypeReference) and (First = nil) and
        MatchText(ANode.Name, ['Variant', 'OleVariant', 'System.Variant', 'System.OleVariant']) then
        First := ANode
      else if (ANode.Kind = TSyntaxKind.TypeDecl) and MatchText(ANode.Name, ['Variant', 'OleVariant']) then
        OwnType := True;
      Result := True;
    end);
  if (First = nil) or OwnType or not WarningEnabled(Tokens, 'IMPLICIT_VARIANTS', First.StartOffset) then
    Exit;
  // Schreibweise wie die übrigen Einträge: ohne Namespace, wenn die Unit SysUtils statt System.SysUtils nennt.
  UnitName := 'System.Variants';
  for Name in Used do
    if MatchText(Name, ['SysUtils', 'Classes']) then
      UnitName := 'Variants';
  Fixes := nil;
  if TUsesClauses.AddUnit(Tokens, First.StartOffset, UnitName, TTextLines.LineBreakOf(AContext.Text), Edit) then
    Fixes := [TRuleFix.Create(Format('%s in uses aufnehmen', [UnitName]), [Edit], True)];
  AReport.Add(TTextRange.Create(First.StartPos, First.EndPos), Format('%s wird ohne System.Variants in uses ' +
    'verwendet (wie W1040).', [First.Name]), TRuleConfidence.High, Fixes);
end;

procedure RegisterUnitRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TUnitNameMismatchRule.Create);
  ARegistry.Register(TTextAfterFinalEndRule.Create);
  ARegistry.Register(TExportsInvalidRule.Create);
  ARegistry.Register(TUnitNameConflictRule.Create);
  ARegistry.Register(TImplicitVariantsUnitRule.Create);
end;

end.
