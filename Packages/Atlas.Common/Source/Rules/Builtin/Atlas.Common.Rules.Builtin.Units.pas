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
//                       einer threadvar, einer Routine mit local, einer
//                       Konstanten oder eines Typs (wie E2276) und derselbe
//                       Exportname zweimal über name '…' (wie E2287).
//                       Variablen und derselbe Eintrag zweimal ohne name
//                       übersetzt Delphi 13 still (#1383).
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
  begin
    for Part in AText.Split(['.']) do
    begin
      if not IsValidIdent(Part) then
      begin
        Exit(False);
      end;
    end;
  end;
end;

/// <summary>Steht das Token an APosition in einem {$IF…}-Zweig?</summary>
function InBranch(const ATokens: TArray<TPascalToken>; const APaths: TArray<string>;
  const APosition: TTextPosition): Boolean;
var
  Index: Integer;
begin
  Result := False;
  if APaths = nil then
  begin
    Exit;
  end;
  for Index := 0 to High(ATokens) do
  begin
    if (ATokens[Index].StartPos.Line = APosition.Line) and
      (ATokens[Index].StartPos.Character = APosition.Character) then
    begin
      Exit(TConditionalBranches.PathAt(APaths, Index) <> '');
    end;
  end;
end;

{ TModuleHeader }

/// <summary>Index des ersten Code-Tokens ab AFrom; hinter dem letzten Token, wenn keins folgt.</summary>
function NextCode(const ATokens: TArray<TPascalToken>; AFrom: Integer): Integer;
begin
  Result := AFrom;
  while (Result <= High(ATokens)) and not IsCode(ATokens[Result]) do
  begin
    Inc(Result);
  end;
end;

/// <summary>Art der Datei nach ihrem ersten Wort.</summary>
function ModuleKindOf(const AToken: TPascalToken): TModuleKind;
begin
  Result := TModuleKind.None;
  if AToken.IsKeyword('unit') then
  begin
    Result := TModuleKind.UnitModule;
  end
  else if AToken.IsKeyword('program') then
  begin
    Result := TModuleKind.ProgramModule;
  end
  else if AToken.IsKeyword('library') then
  begin
    Result := TModuleKind.LibraryModule;
  end
  else if (AToken.Kind = TPascalTokenKind.Identifier) and SameText(AToken.Text, 'package') then
  begin
    Result := TModuleKind.PackageModule;
  end;
end;

/// <summary>Setzt AToken den Namen AName fort? Ein Namensteil am Anfang oder nach einem Punkt.</summary>
function ContinuesName(const AName: string; const AToken: TPascalToken): Boolean;
begin
  if AName = '' then
  begin
    Result := AToken.Kind = TPascalTokenKind.Identifier;
  end
  else
  begin
    Result := (AName[Length(AName)] = '.') and (AToken.Kind in [TPascalTokenKind.Identifier,
      TPascalTokenKind.Keyword]);
  end;
end;

/// <summary>Nimmt das Token AIndex in den Namen auf; False, wenn es nicht mehr dazugehört (danach folgen nur noch
/// Hinweise wie platform).</summary>
function AddNamePart(const ATokens: TArray<TPascalToken>; AIndex: Integer; var AHeader: TModuleHeader): Boolean;
begin
  Result := True;
  if ContinuesName(AHeader.Name, ATokens[AIndex]) then
  begin
    if AHeader.First < 0 then
    begin
      AHeader.First := AIndex;
    end;
    AHeader.Last := AIndex;
    AHeader.Name := AHeader.Name + ATokens[AIndex].Text;
  end
  else if ATokens[AIndex].IsSymbol('.') and (AHeader.Name <> '') then
  begin
    AHeader.Name := AHeader.Name + '.';
  end
  else
  begin
    Result := False;
  end;
end;

/// <summary>Liest den Namen ab dem Token AFrom in AHeader.</summary>
procedure ReadModuleName(const ATokens: TArray<TPascalToken>; AFrom: Integer; var AHeader: TModuleHeader);
var
  mIndex: Integer;
begin
  mIndex := NextCode(ATokens, AFrom);
  while (mIndex <= High(ATokens)) and AddNamePart(ATokens, mIndex, AHeader) do
  begin
    mIndex := NextCode(ATokens, mIndex + 1);
  end;
  // Ein Punkt am Ende gehört nicht zum Namen (halb getippt).
  if EndsStr('.', AHeader.Name) then
  begin
    AHeader.Name := Copy(AHeader.Name, 1, Length(AHeader.Name) - 1);
  end;
end;

class function TModuleHeader.Read(const ATokens: TArray<TPascalToken>): TModuleHeader;
var
  mIndex: Integer;
begin
  Result.Kind := TModuleKind.None;
  Result.Name := '';
  Result.First := -1;
  Result.Last := -1;
  mIndex := NextCode(ATokens, 0);
  if mIndex <= High(ATokens) then
  begin
    Result.Kind := ModuleKindOf(ATokens[mIndex]);
  end;
  if Result.Kind <> TModuleKind.None then
  begin
    ReadModuleName(ATokens, mIndex + 1, Result);
  end;
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
    begin
      Break;
    end;
    if Token.Kind <> TPascalTokenKind.Directive then
    begin
      Continue;
    end;
    Name := TPascalLexer.DirectiveName(Token.Text);
    Body := TDirectiveNames.Body(Token.Text);
    Rest := UpperCase(Trim(Copy(Body, Length(TDirectiveNames.LeadingName(Body)) + 1, MaxInt)));
    if Name = 'WARNINGS' then
    begin
      Result := Rest <> 'OFF';
    end
    else if (Name = 'WARN') and SameText(TDirectiveNames.LeadingName(Rest), AName) then
    begin
      Result := not EndsStr(' OFF', Rest);
    end;
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
  begin
    AText := TFileEncoding.Decode(Bytes, Format);
  end;
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
  begin
    Exit('');
  end;
  Result := Copy(Name, 1, Length(Name) - Length('.pas'));
end;

/// <summary>Kopf der Unit gegen den Dateinamen (E1038).</summary>
procedure CheckOwnName(const AContext: TRuleContext; const AReport: IRuleReport;
  const ATokens: TArray<TPascalToken>);
var
  mHeader: TModuleHeader;
  mExpected, mPath: string;
  mFixes: TArray<TRuleFix>;
  mRange: TTextRange;
begin
  mHeader := TModuleHeader.Read(ATokens);
  mPath := AContext.FileName;
  if mPath = '' then
  begin
    mPath := AContext.RelativePath;
  end;
  mExpected := TUnitNameMismatchRule.ExpectedName(mPath);
  if (mHeader.Kind <> TModuleKind.UnitModule) or (mHeader.Name = '') or (mExpected = '') or
    SameText(mHeader.Name, mExpected) then
  begin
    Exit;
  end;
  if not WarningEnabled(ATokens, 'UNIT_NAME_MISMATCH', ATokens[mHeader.First].Offset) then
  begin
    Exit;
  end;
  mRange := RangeOf(ATokens, mHeader.First, mHeader.Last);
  mFixes := nil;
  if IsQualifiedName(mExpected) then
  begin
    mFixes := [TRuleFix.Create(Format('Unit-Namen in %s ändern', [mExpected]), [TRuleEdit.Create(mRange,
      mExpected)])];
  end;
  AReport.Add(mRange, Format('Unit-Name %s passt nicht zur Datei %s.pas (wie E1038).', [mHeader.Name, mExpected]),
    TRuleConfidence.High, mFixes);
end;

/// <summary>Deklariert die Datei aus uses X in '…' eine andere Unit als X (AUsedName)? Liegt die Ursache in
/// der Unit selbst, meldet dcc dort E1038 (bzw. diese Regel, wenn die Datei geprüft wird).</summary>
function InPathMismatch(const AContext: TRuleContext; const ATokens: TArray<TPascalToken>;
  const APaths: TArray<string>; const AEntry: TUsesListEntry; out AUsedName: string): Boolean;
var
  mText: string;
  mUsed: TModuleHeader;
begin
  AUsedName := '';
  Result := (AEntry.Kind <> TUsesListKind.RequiredPackage) and (AEntry.InPath <> '') and
    ReadNeighbour(AContext, AEntry.InPath, mText) and not InBranch(ATokens, APaths, AEntry.Range.StartPos);
  if not Result then
  begin
    Exit;
  end;
  mUsed := TModuleHeader.Read(TPascalLexer.Tokenize(mText));
  AUsedName := mUsed.Name;
  Result := (mUsed.Kind = TModuleKind.UnitModule) and (mUsed.Name <> '') and not SameText(mUsed.Name, AEntry.Name);
  Result := Result and ((TUnitNameMismatchRule.ExpectedName(AEntry.InPath) = '') or
    SameText(mUsed.Name, TUnitNameMismatchRule.ExpectedName(AEntry.InPath)));
end;

procedure TUnitNameMismatchRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TArray<TPascalToken>;
  mPaths: TArray<string>;
  mEntry: TUsesListEntry;
  mUsedName: string;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  CheckOwnName(AContext, AReport, mTokens);
  // uses X in '…': Die Datei muss die Unit X deklarieren.
  mPaths := TConditionalBranches.Paths(mTokens);
  for mEntry in TUsesUnitNotFoundRule.Entries(mTokens) do
  begin
    if InPathMismatch(AContext, mTokens, mPaths, mEntry, mUsedName) then
    begin
      AReport.Add(mEntry.Range, Format('%s in ''%s'': die Datei deklariert die Unit %s (wie E2085).',
        [mEntry.Name, mEntry.InPath, mUsedName]), TRuleConfidence.High,
        [TRuleFix.Create(Format('In %s ändern', [mUsedName]), [TRuleEdit.Create(mEntry.Range, mUsedName)])]);
    end;
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
  begin
    Exit;
  end;
  Root := AContext.Tree.Root;
  Tokens := AContext.Tree.Tokens;
  // Hinter dem letzten Abschnitt folgen end und der Punkt; beim Programm gehört end zum Block.
  From := Root.Children[Root.ChildCount - 1].EndOffset;
  Index := 0;
  while (Index <= High(Tokens)) and (Tokens[Index].Offset < From) do
  begin
    Inc(Index);
  end;
  while (Index <= High(Tokens)) and not IsCode(Tokens[Index]) do
  begin
    Inc(Index);
  end;
  if (Index <= High(Tokens)) and Tokens[Index].IsKeyword('end') then
  begin
    Inc(Index);
    while (Index <= High(Tokens)) and not IsCode(Tokens[Index]) do
    begin
      Inc(Index);
    end;
  end;
  if (Index <= High(Tokens)) and Tokens[Index].IsSymbol('.') then
  begin
    Result := Index;
  end;
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
  begin
    Exit;
  end;
  Tokens := AContext.Tree.Tokens;
  if TConditionalBranches.PathAt(TConditionalBranches.Paths(Tokens), Dot) <> '' then
  begin
    Exit;
  end;
  if not WarningEnabled(Tokens, '', Tokens[Dot].Offset) then
  begin
    Exit;
  end;
  AllowComments := TRuleOptions.Bool(AContext.Options, 'allowComments', True);
  First := -1;
  for Index := Dot + 1 to High(Tokens) do
  begin
    if IsCode(Tokens[Index]) or not AllowComments then
    begin
      First := Index;
      Break;
    end;
  end;
  if First < 0 then
  begin
    Exit;
  end;
  Message := 'Kommentar nach end. wird nicht übersetzt (wie W1011).';
  for Index := First to High(Tokens) do
  begin
    if IsCode(Tokens[Index]) then
    begin
      Message := 'Code nach end. wird nicht übersetzt (wie W1011).';
    end;
  end;
  // Entfernt wird ab dem Ende des Tokens davor, damit keine Leerzeilen stehen bleiben.
  AReport.Add(RangeOf(Tokens, First, High(Tokens)), Message, TRuleConfidence.High,
    [TRuleFix.Create('Text nach end. entfernen',
    [TRuleEdit.Create(TTextRange.Create(Tokens[First - 1].EndPos, Tokens[High(Tokens)].EndPos), '')])]);
end;

{ TExportsInvalidRule }

function TExportsInvalidRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(ExportsInvalidRuleId, TRuleSeverity.Error,
    'exports-Klausel unzulässig (wie E2191, E2276, E2287)');
end;

/// <summary>Text eines String-Literals ohne Hochkommas ('' wird ').</summary>
function Unquoted(const AText: string): string;
begin
  Result := AText;
  if (Length(Result) >= 2) and (Result[1] = '''') and (Result[Length(Result)] = '''') then
  begin
    Result := Copy(Result, 2, Length(Result) - 2);
  end;
  Result := StringReplace(Result, '''''', '''', [rfReplaceAll]);
end;

type
  /// <summary>Liest die Einträge einer exports-Klausel.</summary>
  TExportsScanner = class
  private
    FTokens: TArray<TPascalToken>;
    FEntries: TArray<TExportEntry>;
    FEntry: TExportEntry;
    FDepth: Integer;
    FLiterals: Integer;
    FInName: Boolean;
    FInParams: Boolean;
    FAfterName: Boolean;
    procedure Finish;
    procedure TrackDepth(const AToken: TPascalToken);
    procedure AddParameter(const AToken: TPascalToken);
    function IsNamePart(const AToken: TPascalToken): Boolean;
    procedure ReadAfterName(const AToken: TPascalToken);
    procedure ReadToken(AIndex: Integer);
  public
    constructor Create(const ATokens: TArray<TPascalToken>);
    function Scan(AFirst, ALast: Integer): TArray<TExportEntry>;
  end;

constructor TExportsScanner.Create(const ATokens: TArray<TPascalToken>);
begin
  inherited Create;
  FTokens := ATokens;
end;

procedure TExportsScanner.Finish;
begin
  if FEntry.Name <> '' then
  begin
    FEntries := FEntries + [FEntry];
  end;
  FEntry := Default(TExportEntry);
  FEntry.First := -1;
  FInName := False;
  FInParams := False;
  FAfterName := False;
  FLiterals := 0;
end;

procedure TExportsScanner.TrackDepth(const AToken: TPascalToken);
begin
  if AToken.IsSymbol('(') then
  begin
    Inc(FDepth);
    if (FDepth = 1) and not FAfterName then
    begin
      FInParams := True;
    end;
  end
  else if AToken.IsSymbol(')') then
  begin
    Dec(FDepth);
  end;
end;

procedure TExportsScanner.AddParameter(const AToken: TPascalToken);
begin
  FEntry.Parameters := FEntry.Parameters + UpperCase(AToken.Text);
  if FDepth = 0 then
  begin
    FInParams := False;
    FAfterName := True;
  end;
end;

/// <summary>Setzt AToken den Namen des Eintrags fort (Bezeichner am Anfang, Teil nach einem Punkt, Punkt nach
/// einem Teil)?</summary>
function TExportsScanner.IsNamePart(const AToken: TPascalToken): Boolean;
begin
  if FEntry.Name = '' then
  begin
    Result := AToken.Kind = TPascalTokenKind.Identifier;
  end
  else if EndsStr('.', FEntry.Name) then
  begin
    Result := AToken.Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword];
  end
  else
  begin
    Result := AToken.IsSymbol('.');
  end;
end;

/// <summary>name, index und resident hinter dem Namen; bei name der Text des ersten String-Literals.</summary>
procedure TExportsScanner.ReadAfterName(const AToken: TPascalToken);
begin
  FAfterName := True;
  if (FDepth = 0) and (AToken.Kind = TPascalTokenKind.Identifier) and
    MatchText(AToken.Text, ['name', 'index', 'resident']) then
  begin
    FInName := SameText(AToken.Text, 'name');
    if FInName then
    begin
      FEntry.HasNameClause := True;
      FLiterals := 0;
    end;
  end
  else if FInName then
  begin
    if (AToken.Kind = TPascalTokenKind.StringLiteral) and (FLiterals = 0) then
    begin
      FEntry.ExportName := Unquoted(AToken.Text);
    end;
    Inc(FLiterals);
  end;
end;

procedure TExportsScanner.ReadToken(AIndex: Integer);
var
  mToken: TPascalToken;
begin
  mToken := FTokens[AIndex];
  if FEntry.First < 0 then
  begin
    FEntry.First := AIndex;
  end;
  FEntry.Last := AIndex;
  TrackDepth(mToken);
  if FInParams then
  begin
    AddParameter(mToken);
  end
  else if not FAfterName and IsNamePart(mToken) then
  begin
    FEntry.Name := FEntry.Name + mToken.Text;
    FEntry.NameLast := AIndex;
  end
  else
  begin
    ReadAfterName(mToken);
  end;
end;

function TExportsScanner.Scan(AFirst, ALast: Integer): TArray<TExportEntry>;
var
  mIndex: Integer;
begin
  FEntries := nil;
  FDepth := 0;
  Finish;
  for mIndex := AFirst + 1 to ALast do
  begin
    if not IsCode(FTokens[mIndex]) then
    begin
      Continue;
    end;
    if (FDepth = 0) and (FTokens[mIndex].IsSymbol(',') or FTokens[mIndex].IsSymbol(';')) then
    begin
      if FEntry.HasNameClause and (FLiterals <> 1) then
      begin
        FEntry.ExportName := '';
      end;
      Finish;
    end
    else
    begin
      ReadToken(mIndex);
    end;
  end;
  // Ohne Semikolon am Ende (halb getippt) zählt der letzte Eintrag nicht.
  Result := FEntries;
end;

class function TExportsInvalidRule.Entries(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer):
  TArray<TExportEntry>;
var
  mScanner: TExportsScanner;
begin
  mScanner := TExportsScanner.Create(ATokens);
  try
    Result := mScanner.Scan(AFirst, ALast);
  finally
    mScanner.Free;
  end;
end;

type
{$SCOPEDENUMS ON}
  TGlobalKind = (Routine, LocalRoutine, ThreadVariable, Variable, Constant, TypeName);
{$SCOPEDENUMS OFF}
  TGlobalKinds = set of TGlobalKind;

/// <summary>Ist die Routine ARoutine mit local deklariert?</summary>
function IsLocalRoutine(ARoutine: TSyntaxNode): Boolean;
var
  mHeader: TSyntaxNode;
  mIndex: Integer;
begin
  Result := False;
  mHeader := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
  if mHeader = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mHeader.ChildCount - 1 do
  begin
    if (mHeader.Children[mIndex].Kind = TSyntaxKind.Directive) and (mHeader.Children[mIndex].Name = 'local') then
    begin
      Result := True;
    end;
  end;
end;

/// <summary>Deklariert der Abschnitt ASection unter seinen Kindern der Art AKind den Namen AName?</summary>
function SectionDeclares(ASection: TSyntaxNode; AKind: TSyntaxKind; const AName: string): Boolean;
var
  mIndex: Integer;
begin
  for mIndex := 0 to ASection.ChildCount - 1 do
  begin
    if (ASection.Children[mIndex].Kind = AKind) and SameText(ASection.Children[mIndex].Name, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Deklariert der var-Abschnitt ASection den Namen AName (auch in A, B: Integer)?</summary>
function VarSectionDeclares(ASection: TSyntaxNode; const AName: string): Boolean;
var
  mIndex: Integer;
  mName: string;
begin
  for mIndex := 0 to ASection.ChildCount - 1 do
  begin
    if ASection.Children[mIndex].Kind <> TSyntaxKind.VarDecl then
    begin
      Continue;
    end;
    for mName in ASection.Children[mIndex].Name.Split([',']) do
    begin
      if SameText(Trim(mName), AName) then
      begin
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

/// <summary>Art der Deklaration AChild, wenn sie AName deklariert; AFound False sonst.</summary>
function DeclarationKind(AChild: TSyntaxNode; const AName: string; out AFound: Boolean): TGlobalKind;
begin
  Result := TGlobalKind.Routine;
  AFound := False;
  case AChild.Kind of
    TSyntaxKind.RoutineDecl:
      begin
        AFound := SameText(AChild.Name, AName);
        if IsLocalRoutine(AChild) then
        begin
          Result := TGlobalKind.LocalRoutine;
        end;
      end;
    TSyntaxKind.VarSection:
      begin
        AFound := VarSectionDeclares(AChild, AName);
        Result := TGlobalKind.Variable;
        if AChild.Name = 'threadvar' then
        begin
          Result := TGlobalKind.ThreadVariable;
        end;
      end;
    TSyntaxKind.ConstSection:
      begin
        AFound := SectionDeclares(AChild, TSyntaxKind.ConstDecl, AName);
        Result := TGlobalKind.Constant;
      end;
    TSyntaxKind.TypeSection:
      begin
        AFound := SectionDeclares(AChild, TSyntaxKind.TypeDecl, AName);
        Result := TGlobalKind.TypeName;
      end;
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

/// <summary>Arten der globalen Deklarationen der Datei je Name in Großbuchstaben. Rekursion nur in interface-
/// und implementation-Abschnitt (höchstens zwei Ebenen, unabhängig von der Ausdruckstiefe).</summary>
function GlobalKinds(ARoot: TSyntaxNode; const AName: string): TGlobalKinds;
var
  mIndex: Integer;
  mChild: TSyntaxNode;
  mKind: TGlobalKind;
  mFound: Boolean;
begin
  Result := [];
  for mIndex := 0 to ARoot.ChildCount - 1 do
  begin
    mChild := ARoot.Children[mIndex];
    if mChild.Kind in [TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection] then
    begin
      Result := Result + GlobalKinds(mChild, AName);
    end
    else
    begin
      mKind := DeclarationKind(mChild, AName, mFound);
      if mFound then
      begin
        Include(Result, mKind);
      end;
    end;
  end;
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
    begin
      Exit(True);
    end;
    Parent := Parent.Parent;
  end;
  Result := False;
end;

type
  /// <summary>Eine exports-Klausel: Token-Indizes von exports und Semikolon und ihre Einträge.</summary>
  TExportsClause = record
    First: Integer;
    Last: Integer;
    Entries: TArray<TExportEntry>;
  end;

/// <summary>Meldung, wenn der Name AName etwas meint, das nicht exportiert werden kann. Sicher fest steht das nur
/// für Namen ohne Punkt, die die Datei global deklariert; '' sonst.</summary>
function ExportKindMessage(ARoot: TSyntaxNode; const AName: string): string;
var
  mKinds: TGlobalKinds;
begin
  Result := '';
  if Pos('.', AName) > 0 then
  begin
    Exit;
  end;
  mKinds := GlobalKinds(ARoot, AName);
  if TGlobalKind.Routine in mKinds then
  begin
    Result := '';
  end
  else if TGlobalKind.LocalRoutine in mKinds then
  begin
    Result := Format('%s ist mit local deklariert und kann nicht exportiert werden (wie E2276).', [AName]);
  end
  else if TGlobalKind.ThreadVariable in mKinds then
  begin
    Result := Format('Die threadvar %s kann nicht exportiert werden (wie E2276).', [AName]);
  end
  // Globale Variablen exportiert dcc (#1383); für einen Typ meldet Delphi 13 E2276, nicht E2121.
  else if mKinds * [TGlobalKind.Constant, TGlobalKind.TypeName] <> [] then
  begin
    Result := Format('%s ist keine Prozedur oder Funktion und kann nicht exportiert werden (wie E2276).',
      [AName]);
  end;
end;

type
  /// <summary>Ein Lauf von exports-invalid über eine Datei.</summary>
  TExportsCheck = class
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FTokens: TArray<TPascalToken>;
    FPaths: TArray<string>;
    FClauses: TArray<TExportsClause>;
    function TokenIndexAt(AOffset: Integer): Integer;
    function RemoveFix(const AClause: TExportsClause; AEntry: Integer): TRuleFix;
    function Exclusive(AFirst, ASecond: Integer): Boolean;
    function ReadClause(ANode: TSyntaxNode; out AClause: TExportsClause): Boolean;
    function IsDuplicate(AClauseIndex, AEntryIndex: Integer): Boolean;
    procedure CheckEntry(AClauseIndex, AEntryIndex: Integer);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    procedure Run(const ANodes: TArray<TSyntaxNode>);
  end;

constructor TExportsCheck.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  FTokens := AContext.Tree.Tokens;
end;

function TExportsCheck.TokenIndexAt(AOffset: Integer): Integer;
begin
  Result := 0;
  while (Result <= High(FTokens)) and (FTokens[Result].Offset < AOffset) do
  begin
    Inc(Result);
  end;
end;

/// <summary>Entfernt den Eintrag AEntry aus AClause samt Komma; als einziger Eintrag die ganze Klausel.</summary>
function TExportsCheck.RemoveFix(const AClause: TExportsClause; AEntry: Integer): TRuleFix;
var
  mRange: TTextRange;
begin
  if Length(AClause.Entries) = 1 then
  begin
    mRange := RangeOf(FTokens, AClause.First, AClause.Last);
  end
  else if AEntry > 0 then
  begin
    mRange := TTextRange.Create(FTokens[AClause.Entries[AEntry - 1].Last].EndPos,
      FTokens[AClause.Entries[AEntry].Last].EndPos);
  end
  else
  begin
    mRange := TTextRange.Create(FTokens[AClause.Entries[0].First].StartPos,
      FTokens[AClause.Entries[1].First].StartPos);
  end;
  Result := TRuleFix.Create('Doppelten Eintrag entfernen', [TRuleEdit.Create(mRange, '')]);
end;

function TExportsCheck.Exclusive(AFirst, ASecond: Integer): Boolean;
begin
  Result := TConditionalBranches.Exclusive(TConditionalBranches.PathAt(FPaths, AFirst),
    TConditionalBranches.PathAt(FPaths, ASecond));
end;

/// <summary>Liest die Klausel ANode; False, wenn sie unvollständig ist oder in einer Routine steht (E2191).
/// </summary>
function TExportsCheck.ReadClause(ANode: TSyntaxNode; out AClause: TExportsClause): Boolean;
begin
  AClause.First := TokenIndexAt(ANode.StartOffset);
  AClause.Last := TokenIndexAt(ANode.EndOffset) - 1;
  AClause.Entries := nil;
  Result := (AClause.First <= High(FTokens)) and FTokens[AClause.First].IsKeyword('exports') and
    FTokens[AClause.Last].IsSymbol(';');
  if Result and InRoutine(ANode) then
  begin
    FReport.Add(RangeOf(FTokens, AClause.First, AClause.First),
      'exports ist nur auf globaler Ebene erlaubt (wie E2191).', TRuleConfidence.High);
    Result := False;
  end;
  if Result then
  begin
    AClause.Entries := TExportsInvalidRule.Entries(FTokens, AClause.First, AClause.Last);
  end;
end;

/// <summary>Steht derselbe Exportname weiter vorn? Denselben Eintrag zweimal ohne name übersetzt Delphi 13
/// (#1383).</summary>
function TExportsCheck.IsDuplicate(AClauseIndex, AEntryIndex: Integer): Boolean;
var
  mEntry, mEarlier: TExportEntry;
  mOther, mOtherEntry: Integer;
begin
  mEntry := FClauses[AClauseIndex].Entries[AEntryIndex];
  if mEntry.ExportName = '' then
  begin
    Exit(False);
  end;
  for mOther := 0 to AClauseIndex do
  begin
    for mOtherEntry := 0 to High(FClauses[mOther].Entries) do
    begin
      if (mOther = AClauseIndex) and (mOtherEntry >= AEntryIndex) then
      begin
        Break;
      end;
      mEarlier := FClauses[mOther].Entries[mOtherEntry];
      if not Exclusive(mEarlier.First, mEntry.First) and (mEntry.ExportName = mEarlier.ExportName) then
      begin
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

procedure TExportsCheck.CheckEntry(AClauseIndex, AEntryIndex: Integer);
var
  mEntry: TExportEntry;
  mMessage: string;
begin
  mEntry := FClauses[AClauseIndex].Entries[AEntryIndex];
  mMessage := ExportKindMessage(FContext.Tree.Root, mEntry.Name);
  if mMessage <> '' then
  begin
    FReport.Add(RangeOf(FTokens, mEntry.First, mEntry.NameLast), mMessage, TRuleConfidence.High);
  end;
  if IsDuplicate(AClauseIndex, AEntryIndex) then
  begin
    FReport.Add(RangeOf(FTokens, mEntry.First, mEntry.Last), Format('Der Name ''%s'' wird zweimal exportiert ' +
      '(wie E2287).', [mEntry.ExportName]), TRuleConfidence.High, [RemoveFix(FClauses[AClauseIndex],
      AEntryIndex)]);
  end;
end;

procedure TExportsCheck.Run(const ANodes: TArray<TSyntaxNode>);
var
  mNode: TSyntaxNode;
  mClause: TExportsClause;
  mClauseIndex, mEntryIndex: Integer;
begin
  FPaths := TConditionalBranches.Paths(FTokens);
  FClauses := nil;
  for mNode in ANodes do
  begin
    if ReadClause(mNode, mClause) then
    begin
      FClauses := FClauses + [mClause];
    end;
  end;
  for mClauseIndex := 0 to High(FClauses) do
  begin
    for mEntryIndex := 0 to High(FClauses[mClauseIndex].Entries) do
    begin
      CheckEntry(mClauseIndex, mEntryIndex);
    end;
  end;
end;

/// <summary>Alle exports-Klauseln im Baum.</summary>
function ExportsNodes(ARoot: TSyntaxNode): TArray<TSyntaxNode>;
var
  mNodes: TArray<TSyntaxNode>;
begin
  mNodes := nil;
  ARoot.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      if ANode.Kind = TSyntaxKind.ExportsClause then
      begin
        mNodes := mNodes + [ANode];
      end;
      Result := True;
    end);
  Result := mNodes;
end;

procedure TExportsInvalidRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mNodes: TArray<TSyntaxNode>;
  mCheck: TExportsCheck;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mNodes := ExportsNodes(AContext.Tree.Root);
  if mNodes = nil then
  begin
    Exit;
  end;
  mCheck := TExportsCheck.Create(AContext, AReport);
  try
    mCheck.Run(mNodes);
  finally
    mCheck.Free;
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
  begin
    Exit;
  end;
  Tokens := AContext.Tree.Tokens;
  Header := TModuleHeader.Read(Tokens);
  Path := StringReplace(AContext.FileName + '|' + AContext.RelativePath, '\', '/', [rfReplaceAll]);
  if (Header.Kind = TModuleKind.UnitModule) and MatchText(Header.Name, ['System', 'SysInit']) and
    not ContainsText(Path, 'source/rtl/') then
  begin
    AReport.Add(RangeOf(Tokens, Header.First, Header.Last), Format('Der Unit-Name %s ist für den Compiler ' +
      'reserviert (wie E2272).', [Header.Name]), TRuleConfidence.High);
  end;
  // {$NOINCLUDE X} braucht eine Unit, die der Compiler kennt.
  if AContext.Units = nil then
  begin
    Exit;
  end;
  for Token in Tokens do
  begin
    if (Token.Kind <> TPascalTokenKind.Directive) or (TPascalLexer.DirectiveName(Token.Text) <> 'NOINCLUDE') then
    begin
      Continue;
    end;
    Body := TDirectiveNames.Body(Token.Text);
    Name := Trim(Copy(Body, Length(TDirectiveNames.LeadingName(Body)) + 1, MaxInt));
    if not IsQualifiedName(Name) or (Token.StartPos.Line <> Token.EndPos.Line) then
    begin
      Continue;
    end;
    if AContext.Units.Find(Name, '', AContext.FileName, [TRuleUnitSource.Project]) <> TRuleUnitAnswer.Missing then
    begin
      Continue;
    end;
    At := Pos(Name, Token.Text);
    Range := TTextRange.Create(Token.StartPos.Line, Token.StartPos.Character + At - 1, Token.StartPos.Line,
      Token.StartPos.Character + At - 1 + Length(Name));
    Fixes := nil;
    for Suggestion in TUsesUnitNotFoundRule.Suggestions(Name, AContext.Units.KnownUnits([TRuleUnitSource.Project])) do
    begin
      Fixes := Fixes + [TRuleFix.Create(Format('%s verwenden', [Suggestion]), [TRuleEdit.Create(Range, Suggestion)])];
    end;
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

/// <summary>Nennt die uses-Liste AUsed System.Variants oder Variants?</summary>
function UsesVariants(const AUsed: TArray<string>): Boolean;
var
  mName: string;
begin
  for mName in AUsed do
  begin
    if MatchText(mName, ['System.Variants', 'Variants']) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Schreibweise wie die übrigen Einträge: ohne Namespace, wenn die Unit SysUtils statt System.SysUtils
/// nennt.</summary>
function VariantsUnitName(const AUsed: TArray<string>): string;
var
  mName: string;
begin
  Result := 'System.Variants';
  for mName in AUsed do
  begin
    if MatchText(mName, ['SysUtils', 'Classes']) then
    begin
      Result := 'Variants';
    end;
  end;
end;

/// <summary>Erste Typangabe Variant oder OleVariant; nil, wenn die Datei einen eigenen Typ dieses Namens
/// deklariert oder keine hat.</summary>
function FirstVariantUse(ARoot: TSyntaxNode): TSyntaxNode;
var
  mFirst: TSyntaxNode;
  mOwnType: Boolean;
begin
  mFirst := nil;
  mOwnType := False;
  ARoot.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      if (ANode.Kind = TSyntaxKind.TypeReference) and (mFirst = nil) and
        MatchText(ANode.Name, ['Variant', 'OleVariant', 'System.Variant', 'System.OleVariant']) then
      begin
        mFirst := ANode;
      end
      else if (ANode.Kind = TSyntaxKind.TypeDecl) and MatchText(ANode.Name, ['Variant', 'OleVariant']) then
      begin
        mOwnType := True;
      end;
      Result := True;
    end);
  Result := mFirst;
  if mOwnType then
  begin
    Result := nil;
  end;
end;

procedure TImplicitVariantsUnitRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TArray<TPascalToken>;
  mUsed: TArray<string>;
  mUnitName: string;
  mFirst: TSyntaxNode;
  mEdit: TTextEdit;
  mFixes: TArray<TRuleFix>;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  mUsed := TUsesClauses.UsedUnits(mTokens);
  if MatchText(TModuleHeader.Read(mTokens).Name, ['System', 'SysInit', 'System.Variants', 'Variants']) or
    UsesVariants(mUsed) then
  begin
    Exit;
  end;
  mFirst := FirstVariantUse(AContext.Tree.Root);
  if (mFirst = nil) or not WarningEnabled(mTokens, 'IMPLICIT_VARIANTS', mFirst.StartOffset) then
  begin
    Exit;
  end;
  mUnitName := VariantsUnitName(mUsed);
  mFixes := nil;
  if TUsesClauses.AddUnit(mTokens, mFirst.StartOffset, mUnitName, TTextLines.LineBreakOf(AContext.Text), mEdit) then
  begin
    mFixes := [TRuleFix.Create(Format('%s in uses aufnehmen', [mUnitName]), [mEdit], True)];
  end;
  AReport.Add(TTextRange.Create(mFirst.StartPos, mFirst.EndPos), Format('%s wird ohne System.Variants in uses ' +
    'verwendet (wie W1040).', [mFirst.Name]), TRuleConfidence.High, mFixes);
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
