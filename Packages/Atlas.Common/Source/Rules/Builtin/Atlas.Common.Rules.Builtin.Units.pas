unit Atlas.Common.Rules.Builtin.Units;

// Regeln für Unit-Kopf, uses und Dateiende (#909, Gruppe Compiler vorab):
//   unit-name-mismatch  Der Name hinter unit weicht vom Dateinamen ab (#990,
//                       wie E1038, W1038), oder die Datei aus "uses X in
//                       '…'" deklariert eine andere Unit als X (wie E2085).
//
// Die Regeln lesen nur den Text der Datei und, für "in '…'", die genannte
// Datei über TRuleContext.ReadFile. Ohne Dateinamen, ohne lesbare Datei und
// für Einträge in {$IF…}-Zweigen schweigen sie. {$WARN UNIT_NAME_MISMATCH
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
    AReport.Add(Entry.Range, Format('%s in ''%s'': die Datei deklariert die Unit %s (wie E2085).',
      [Entry.Name, Entry.InPath, Used.Name]), TRuleConfidence.High,
      [TRuleFix.Create(Format('In %s ändern', [Used.Name]), [TRuleEdit.Create(Entry.Range, Used.Name)])]);
  end;
end;

procedure RegisterUnitRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TUnitNameMismatchRule.Create);
end;

end.
