unit Atlas.Common.Rules.Builtin.Inheritance.OverrideTargets;

// Regel override-target-missing aus Atlas.Common.Rules.Builtin.Inheritance (#997): override ohne passende
// virtuelle Methode im Vorfahren (E2137), auf eine statische (E2170) oder finale (E2352), Ableiten von einer
// sealed-Klasse (E2353).

interface

uses
  Atlas.Common.Rules.Contract;

type
  TOverrideTargetMissingRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.Builtin.Naming,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.ClassActions,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Text.Fuzzy,
  Atlas.Common.Rules.Builtin.Inheritance.Ancestry,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TInheritanceOverrideTargetsText = (Title, TakeSignature, Final, NotVirtual, OtherName, NoAncestor, NoAncestorMeant,
    Sealed);

const
  cTexts: array[TInheritanceOverrideTargetsText] of TAtlasText = (
    (De: 'override ohne passende virtuelle Methode im Vorfahren';
     En: 'override without matching virtual method in the ancestor'),
    (De: 'Signatur von %s.%s übernehmen'; En: 'Take signature of %s.%s'),
    (De: '%s.%s ist final und lässt sich nicht überschreiben (wie E2352).';
     En: '%s.%s is final and cannot be overridden (like E2352).'),
    (De: '%s.%s ist nicht virtuell; override braucht virtual oder dynamic im Vorfahren (wie E2170).';
     En: '%s.%s is not virtual; override needs virtual or dynamic in the ancestor (like E2170).'),
    (De: '%s hat kein virtuelles %s; dort heißt es %s (wie E2137).';
     En: '%s has no virtual %s; there it is called %s (like E2137).'),
    (De: 'Kein Vorfahr von %s hat ein virtuelles %s (wie E2137).';
     En: 'No ancestor of %s has a virtual %s (like E2137).'),
    (De: 'Kein Vorfahr von %s hat ein virtuelles %s; gemeint ist wohl %s (wie E2137).';
     En: 'No ancestor of %s has a virtual %s; %s is probably meant (like E2137).'),
    (De: '%s ist sealed; davon lässt sich nicht ableiten (wie E2353).';
     En: '%s is sealed; it cannot be derived from (like E2353).'));

{$SCOPEDENUMS OFF}

{ TOverrideTargetMissingRule }

type
  /// <summary>Gleichnamige Methode eines Vorfahren für override-target-missing (#997).</summary>
  TOverrideCandidate = record
    TypeName: string;
    Symbol: TIndexSymbol;
    /// <summary>procedure, function, constructor oder destructor aus der Signatur.</summary>
    Keyword: string;
    /// <summary>Kopf ab dem Namen ohne Direktiven, z. B. "Ausfuehren(const Modus: TModus)".</summary>
    Head: string;
  end;

  /// <summary>Vergleich zweier Köpfe: gleich, nur Typen anders, anders gebaut.</summary>
  TOverrideMatch = (Same, OtherTypes, Different);

/// <summary>Schlüsselwort und Kopf ab dem Namen aus einer Signatur wie "procedure Foo(A: Integer); virtual;".
/// </summary>
function SplitSignature(const ASignature: string; out AKeyword, AHead: string): Boolean;
var
  Text: string;
  Index, Depth: Integer;
begin
  Text := Trim(ASignature);
  AKeyword := LowerCase(Copy(Text, 1, Pos(' ', Text + ' ') - 1));
  AHead := '';
  Result := MatchText(AKeyword, ['procedure', 'function', 'constructor', 'destructor']);
  if not Result then
  begin
    Exit;
  end;
  Text := Trim(Copy(Text, Length(AKeyword) + 1, MaxInt));
  Depth := 0;
  for Index := 1 to Length(Text) do
    case Text[Index] of
      '(', '[':
        Inc(Depth);
      ')', ']':
        Dec(Depth);
      ';':
        if Depth = 0 then
        begin
          AHead := Trim(Copy(Text, 1, Index - 1));
          Exit;
        end;
    end;
  AHead := Text;
end;

/// <summary>Verfolgt Klammertiefe und Standardwert-Abschnitte für WithoutDefaults: ab "=" auf Tiefe 1 wird bis
/// zum nächsten ";" bzw. zur schließenden Klammer übersprungen.</summary>
procedure TrackDefault(AChar: Char; var ADepth: Integer; var ASkipping: Boolean);
begin
  case AChar of
    '(', '[':
      Inc(ADepth);
    ')', ']':
      begin
        Dec(ADepth);
        ASkipping := ASkipping and (ADepth <> 0);
      end;
    ';':
      ASkipping := ASkipping and (ADepth <> 1);
    '=':
      ASkipping := ASkipping or (ADepth = 1);
  end;
end;

/// <summary>Kopf ohne Standardwerte der Parameter, für den Rumpf.</summary>
function WithoutDefaults(const AHead: string): string;
var
  Index, Depth: Integer;
  Skipping: Boolean;
  Quoted: Boolean;
begin
  Result := '';
  Depth := 0;
  Skipping := False;
  Quoted := False;
  for Index := 1 to Length(AHead) do
  begin
    if AHead[Index] = '''' then
    begin
      Quoted := not Quoted;
    end;
    if not Quoted then
    begin
      TrackDefault(AHead[Index], Depth, Skipping);
    end;
    if not Skipping then
    begin
      Result := Result + AHead[Index];
    end;
  end;
  Result := StringReplace(Result, ' ;', ';', [rfReplaceAll]);
  Result := StringReplace(Result, ' )', ')', [rfReplaceAll]);
end;

/// <summary>Hängt die nicht leeren Typparameter aus ATypeParams ("T, U") an AList.</summary>
procedure AppendTypeParams(var AList: TArray<string>; const ATypeParams: string);
var
  Name: string;
begin
  for Name in SplitString(ATypeParams, ',') do
  begin
    if Trim(Name) <> '' then
    begin
      AList := AList + [Trim(Name)];
    end;
  end;
end;

/// <summary>AMethod und ACandidate passen im Aufbau zusammen: Schlüsselwort, Parameterzahl, Rückgabe ja/nein.
/// </summary>
function SameShape(const AMethod: TMethodDecl; const ACandidate: TOverrideCandidate): Boolean;
begin
  Result := (ACandidate.Keyword = AMethod.Keyword) and (AMethod.Symbol.MaxArgs = ACandidate.Symbol.MaxArgs);
  Result := Result and (Length(AMethod.Symbol.ParamTypes) = Length(ACandidate.Symbol.ParamTypes)) and
    ((AMethod.Symbol.TypeName = '') = (ACandidate.Symbol.TypeName = ''));
end;

/// <summary>Kandidat aus der Methode ASymbol der Stufe ALocation: gleichnamig (oder AName leer), für den
/// Nachfahren sichtbar, keine Klassenmethode, Signatur lesbar.</summary>
function CandidateOf(const ALocation: TSymbolLocation; const ASymbol: TIndexSymbol; const AName: string;
  out AItem: TOverrideCandidate): Boolean;
begin
  AItem := Default(TOverrideCandidate);
  Result := ((AName = '') or SameText(ASymbol.Name, AName)) and not InvisibleToDescendant(ALocation, ASymbol) and
    not StartsText('class ', ASymbol.Signature);
  if Result then
  begin
    AItem.TypeName := ALocation.Symbol.Name;
    AItem.Symbol := ASymbol;
    Result := SplitSignature(ASymbol.Signature, AItem.Keyword, AItem.Head);
  end;
end;

/// <summary>Kopf der eigenen Methode aus den Parametertypen, für die Meldung.</summary>
function OwnHead(const AMethod: TMethodDecl): string;
begin
  Result := AMethod.Symbol.Name + '(' + string.Join(', ', AMethod.Symbol.ParamTypes) + ')';
  if AMethod.Symbol.TypeName <> '' then
  begin
    Result := Result + ': ' + AMethod.Symbol.TypeName;
  end;
end;

/// <summary>TObject.Destroy als Kandidat, wenn System nicht im Index steht.</summary>
function ObjectDestroy: TOverrideCandidate;
begin
  Result := Default(TOverrideCandidate);
  Result.TypeName := 'TObject';
  Result.Symbol.Name := 'Destroy';
  Result.Keyword := 'destructor';
  Result.Head := 'Destroy';
end;

/// <summary>Die Signatur eines Vorfahren nennt "class sealed" oder "class abstract sealed".</summary>
function IsSealedSignature(const ASignature: string): Boolean;
var
  Words: TArray<string>;
  Index: Integer;
begin
  Words := LowerCase(ASignature).Split([' ', '(', ')', '<', '>', '=', ';'], TStringSplitOptions.ExcludeEmpty);
  Result := False;
  Index := 0;
  while not Result and (Index < High(Words)) do
  begin
    Result := (Words[Index] = 'class') and ((Words[Index + 1] = 'sealed') or ((Words[Index + 1] = 'abstract') and
      (Index + 2 <= High(Words)) and (Words[Index + 2] = 'sealed')));
    Inc(Index);
  end;
end;

type
  /// <summary>Ähnlichster virtueller Kandidat mit anderem Kopf.</summary>
  TBestCandidate = record
    Candidate: TOverrideCandidate;
    Match: TOverrideMatch;
    /// <summary>Alle abweichenden Typen stehen sicher für sich (kein unbekannter Alias).</summary>
    Certain: Boolean;
  end;

  /// <summary>Prüfung einer Unit für override-target-missing; hält die gerade geprüfte Methode mit Vorfahrenkette,
  /// Typparametern und gleichnamigen Kandidaten.</summary>
  TOverrideTargetCheck = class
  strict private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FCache: IRuleDerivedCache;
    FAncestry: TAncestry;
    FTokens: TArray<TPascalToken>;
    FMethod: TMethodDecl;
    FChain: TArray<TSymbolLocation>;
    FComplete: Boolean;
    FObjectMissing: Boolean;
    FWildcards: TArray<string>;
    FFound: TArray<TOverrideCandidate>;
    function Wildcards: TArray<string>;
    procedure CompareType(const A, B: string; var AMatch: TOverrideMatch; var ACertain: Boolean);
    function CompareTypes(const ACandidate: TOverrideCandidate; out ACertain: Boolean): TOverrideMatch;
    function Compare(const ACandidate: TOverrideCandidate): TOverrideMatch;
    function Candidates(const AName: string): TArray<TOverrideCandidate>;
    function IsSymbolAt(AIndex: Integer; const ATexts: array of string): Boolean;
    function TokenIndex(AOffset: Integer): Integer;
    function HeadEnd(AFrom: Integer): Integer;
    function IsBodyHead(AIndex: Integer): Boolean;
    function BodyStart: Integer;
    function AdoptFix(const ACandidate: TOverrideCandidate; out AFix: TRuleFix): Boolean;
    procedure Prepare(const AMethod: TMethodDecl);
    function ReportTarget: Boolean;
    function ReportStatic: Boolean;
    function FindBest(out ABest: TBestCandidate): Boolean;
    function ReportOtherHead: Boolean;
    function TypoNames(out AVirtuals: TArray<TOverrideCandidate>): TArray<string>;
    function TypoFixes(const AVirtuals: TArray<TOverrideCandidate>; const ATypo: string): TArray<TRuleFix>;
    procedure ReportTypo;
    procedure CheckMethod(const AMethod: TMethodDecl);
    procedure CheckSealed;
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    destructor Destroy; override;
    procedure Run;
  end;

function TOverrideTargetMissingRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('override-target-missing', TRuleSeverity.Error,
    cTexts[TInheritanceOverrideTargetsText.Title].Text);
end;

procedure TOverrideTargetMissingRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Check: TOverrideTargetCheck;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  Check := TOverrideTargetCheck.Create(AContext, AReport);
  try
    Check.Run;
  finally
    Check.Free;
  end;
end;

{ TOverrideTargetCheck }

constructor TOverrideTargetCheck.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  FTokens := AContext.Tree.Tokens;
  FCache := TRuleDerived.Open(AContext);
  FAncestry := TAncestry.Create(AContext.Index, TRuleDerived.UnitIndex(FCache, AContext));
end;

destructor TOverrideTargetCheck.Destroy;
begin
  FAncestry.Free;
  inherited Destroy;
end;

/// <summary>Typparameter der Vorfahrenkette und der eigenen Klasse; sie passen auf jeden Typ.</summary>
function TOverrideTargetCheck.Wildcards: TArray<string>;
var
  Location: TSymbolLocation;
  Symbol: TIndexSymbol;
begin
  Result := nil;
  for Location in FChain do
  begin
    AppendTypeParams(Result, Location.Symbol.TypeParams);
  end;
  for Symbol in FAncestry.Local.Symbols do
  begin
    if (Symbol.Kind = TIndexSymbolKind.ClassType) and SameText(Symbol.Name, FMethod.ClassName) then
    begin
      AppendTypeParams(Result, Symbol.TypeParams);
    end;
  end;
end;

/// <summary>Weichen die Typen A und B ab, wird AMatch zu OtherTypes; ACertain bleibt nur, wenn beide bekannt sind.
/// </summary>
procedure TOverrideTargetCheck.CompareType(const A, B: string; var AMatch: TOverrideMatch; var ACertain: Boolean);
begin
  if not FAncestry.SameType(A, B, FWildcards) then
  begin
    AMatch := TOverrideMatch.OtherTypes;
    ACertain := ACertain and FAncestry.KnownType(A) and FAncestry.KnownType(B);
  end;
end;

/// <summary>Wie Compare; ACertain: alle abweichenden Typen stehen sicher für sich.</summary>
function TOverrideTargetCheck.CompareTypes(const ACandidate: TOverrideCandidate;
  out ACertain: Boolean): TOverrideMatch;
var
  Index: Integer;
  Own, Other: TArray<string>;
begin
  ACertain := True;
  if not SameShape(FMethod, ACandidate) then
  begin
    Exit(TOverrideMatch.Different);
  end;
  Result := TOverrideMatch.Same;
  Own := FMethod.Symbol.ParamTypes;
  Other := ACandidate.Symbol.ParamTypes;
  for Index := 0 to High(Own) do
  begin
    if (Own[Index] = '') <> (Other[Index] = '') then
    begin
      Exit(TOverrideMatch.Different);
    end;
    CompareType(Own[Index], Other[Index], Result, ACertain);
  end;
  CompareType(FMethod.Symbol.TypeName, ACandidate.Symbol.TypeName, Result, ACertain);
end;

function TOverrideTargetCheck.Compare(const ACandidate: TOverrideCandidate): TOverrideMatch;
var
  Certain: Boolean;
begin
  Result := CompareTypes(ACandidate, Certain);
end;

/// <summary>Gleichnamige (AName leer: alle), im Nachfahren sichtbare Methoden der Vorfahren, der nächste zuerst.
/// </summary>
function TOverrideTargetCheck.Candidates(const AName: string): TArray<TOverrideCandidate>;
var
  Location: TSymbolLocation;
  Symbol: TIndexSymbol;
  Item: TOverrideCandidate;
begin
  Result := nil;
  for Location in FChain do
  begin
    for Symbol in FAncestry.Methods(Location) do
    begin
      if CandidateOf(Location, Symbol, AName, Item) then
      begin
        Result := Result + [Item];
      end;
    end;
  end;
end;

function TOverrideTargetCheck.IsSymbolAt(AIndex: Integer; const ATexts: array of string): Boolean;
begin
  Result := (FTokens[AIndex].Kind = TPascalTokenKind.Symbol) and MatchStr(FTokens[AIndex].Text, ATexts);
end;

/// <summary>Index des Tokens, das bei AOffset beginnt; -1 ohne.</summary>
function TOverrideTargetCheck.TokenIndex(AOffset: Integer): Integer;
begin
  // Binär statt ab Dateianfang (#1342).
  Result := TSyntaxTree.FirstTokenOf(FTokens, AOffset);
  if (Result > High(FTokens)) or (FTokens[Result].Offset <> AOffset) then
  begin
    Result := -1;
  end;
end;

/// <summary>Erstes ";" auf Klammertiefe 0 ab dem Token AFrom; -1 ohne.</summary>
function TOverrideTargetCheck.HeadEnd(AFrom: Integer): Integer;
var
  Depth: Integer;
begin
  Depth := 0;
  Result := AFrom;
  while (Result <= High(FTokens)) and ((Depth <> 0) or not IsSymbolAt(Result, [';'])) do
  begin
    if IsSymbolAt(Result, ['(', '[']) then
    begin
      Inc(Depth);
    end
    else if IsSymbolAt(Result, [')', ']']) then
    begin
      Dec(Depth);
    end;
    Inc(Result);
  end;
  if Result > High(FTokens) then
  begin
    Result := -1;
  end;
end;

/// <summary>Bei AIndex steht "Klasse.Name" der geprüften Methode hinter procedure/function/constructor/destructor.
/// </summary>
function TOverrideTargetCheck.IsBodyHead(AIndex: Integer): Boolean;
begin
  Result := (FTokens[AIndex].Kind = TPascalTokenKind.Identifier) and SameText(FTokens[AIndex].Text, FMethod.ClassName);
  Result := Result and (FTokens[AIndex + 1].Text = '.') and SameText(FTokens[AIndex + 2].Text, FMethod.Symbol.Name);
  Result := Result and (FTokens[AIndex - 1].Kind = TPascalTokenKind.Keyword) and MatchText(FTokens[AIndex - 1].Text,
    ['procedure', 'function', 'constructor', 'destructor']);
end;

/// <summary>Kopf des einzigen Rumpfs der geprüften Methode: Index des Schlüsselworts; -1 ohne oder bei mehreren.
/// </summary>
function TOverrideTargetCheck.BodyStart: Integer;
var
  Index: Integer;
begin
  Result := -1;
  for Index := 1 to High(FTokens) - 2 do
  begin
    if IsBodyHead(Index) then
    begin
      if Result >= 0 then
      begin
        Exit(-1);
      end;
      Result := Index - 1;
    end;
  end;
end;

/// <summary>Übernimmt Schlüsselwort und Kopf von ACandidate in Deklaration und, wenn eindeutig, Rumpf.</summary>
function TOverrideTargetCheck.AdoptFix(const ACandidate: TOverrideCandidate; out AFix: TRuleFix): Boolean;
var
  First, Last, Body, BodyLast: Integer;
  Edits: TArray<TRuleEdit>;
begin
  AFix := Default(TRuleFix);
  First := TokenIndex(FMethod.Header.StartOffset);
  Last := -1;
  if First >= 0 then
  begin
    Last := HeadEnd(First);
  end;
  Result := Last > First;
  if not Result then
  begin
    Exit;
  end;
  Edits := [TRuleEdit.Create(TTextRange.Create(FTokens[First].StartPos, FTokens[Last].StartPos),
    ACandidate.Keyword + ' ' + ACandidate.Head)];
  Body := BodyStart;
  BodyLast := -1;
  if Body > Last then
  begin
    BodyLast := HeadEnd(Body);
  end;
  if BodyLast > Body then
  begin
    Edits := Edits + [TRuleEdit.Create(TTextRange.Create(FTokens[Body].StartPos, FTokens[BodyLast].StartPos),
      ACandidate.Keyword + ' ' + FMethod.ClassName + '.' + WithoutDefaults(ACandidate.Head))];
  end;
  AFix := TRuleFix.Create(cTexts[TInheritanceOverrideTargetsText.TakeSignature].Fmt([ACandidate.TypeName,
    ACandidate.Symbol.Name]),
    Edits);
end;

/// <summary>Vorfahrenkette ab der Klasse, in deren Rumpf die Methode steht (#1326): THorseChannel&lt;T&gt; neben
/// THorseChannel; dazu Typparameter und gleichnamige Kandidaten.</summary>
procedure TOverrideTargetCheck.Prepare(const AMethod: TMethodDecl);
var
  Own: TSymbolLocation;
begin
  FMethod := AMethod;
  if FAncestry.OwnerOf(AMethod.Symbol, Own) then
  begin
    FChain := FAncestry.Ancestors(Own, FComplete, FObjectMissing);
  end
  else
  begin
    FChain := FAncestry.Ancestors(AMethod.ClassName, FComplete, FObjectMissing);
  end;
  FWildcards := Wildcards;
  FFound := Candidates(AMethod.Symbol.Name);
end;

/// <summary>Die nächste virtuelle Methode mit gleichem Kopf ist das Ziel; final meldet E2352.</summary>
function TOverrideTargetCheck.ReportTarget: Boolean;
var
  Candidate: TOverrideCandidate;
begin
  Result := False;
  for Candidate in FFound do
  begin
    if Candidate.Symbol.IsVirtual and (Compare(Candidate) = TOverrideMatch.Same) then
    begin
      if Candidate.Symbol.HasDirective('final') then
      begin
        FReport.Add(FMethod.Symbol.SelectionRange,
          cTexts[TInheritanceOverrideTargetsText.Final].Fmt([Candidate.TypeName, Candidate.Symbol.Name]),
          TRuleConfidence.High);
      end;
      Exit(True);
    end;
  end;
end;

/// <summary>Gleicher Kopf, aber nicht virtuell (E2170).</summary>
function TOverrideTargetCheck.ReportStatic: Boolean;
var
  Candidate: TOverrideCandidate;
begin
  Result := False;
  for Candidate in FFound do
  begin
    if Compare(Candidate) = TOverrideMatch.Same then
    begin
      FReport.Add(FMethod.Symbol.SelectionRange,
        cTexts[TInheritanceOverrideTargetsText.NotVirtual].Fmt([Candidate.TypeName, Candidate.Symbol.Name]),
        TRuleConfidence.High);
      Exit(True);
    end;
  end;
end;

/// <summary>Virtuelle Methode gleichen Namens mit anderem Kopf: die ähnlichste der nächsten Stufe.</summary>
function TOverrideTargetCheck.FindBest(out ABest: TBestCandidate): Boolean;
var
  Candidate: TOverrideCandidate;
  Match: TOverrideMatch;
  Certain: Boolean;
begin
  Result := False;
  ABest := Default(TBestCandidate);
  for Candidate in FFound do
  begin
    if not Candidate.Symbol.IsVirtual then
    begin
      Continue;
    end;
    Match := CompareTypes(Candidate, Certain);
    if not Result or (Match < ABest.Match) then
    begin
      ABest.Candidate := Candidate;
      ABest.Match := Match;
      ABest.Certain := Certain;
      Result := True;
    end;
  end;
end;

/// <summary>Meldet E2137 mit dem Kopf der ähnlichsten virtuellen Methode gleichen Namens.</summary>
function TOverrideTargetCheck.ReportOtherHead: Boolean;
var
  Best: TBestCandidate;
  Confidence: TRuleConfidence;
  Fixes: TArray<TRuleFix>;
  Fix: TRuleFix;
begin
  Result := FindBest(Best);
  if not Result then
  begin
    Exit;
  end;
  Confidence := TRuleConfidence.High;
  // Nur andere Typen: sicher nur, wenn keiner ein unbekannter Alias sein kann.
  if (Best.Match = TOverrideMatch.OtherTypes) and not Best.Certain then
  begin
    Confidence := TRuleConfidence.Medium;
  end;
  Fixes := nil;
  if (FWildcards = nil) and AdoptFix(Best.Candidate, Fix) then
  begin
    Fixes := [Fix];
  end;
  FReport.Add(FMethod.Symbol.SelectionRange, cTexts[TInheritanceOverrideTargetsText.OtherName].Fmt(
    [Best.Candidate.TypeName, OwnHead(FMethod), Best.Candidate.Head]), Confidence, Fixes);
end;

/// <summary>Namen aller virtuellen Methoden gleicher Art der Vorfahren (dazu die von TObject, wenn System nicht im
/// Index steht); AVirtuals die zugehörigen Kandidaten.</summary>
function TOverrideTargetCheck.TypoNames(out AVirtuals: TArray<TOverrideCandidate>): TArray<string>;
var
  Candidate: TOverrideCandidate;
  Name: string;
begin
  AVirtuals := nil;
  Result := nil;
  for Candidate in Candidates('') do
  begin
    if Candidate.Symbol.IsVirtual and (Candidate.Keyword = FMethod.Keyword) then
    begin
      AVirtuals := AVirtuals + [Candidate];
      Result := Result + [Candidate.Symbol.Name];
    end;
  end;
  if FObjectMissing then
  begin
    for Name in ObjectVirtualNames do
    begin
      Result := Result + [Name];
    end;
  end;
end;

/// <summary>Korrektur auf den vermuteten Namen ATypo: Kopf des Kandidaten übernehmen, sonst TObject.Destroy.
/// </summary>
function TOverrideTargetCheck.TypoFixes(const AVirtuals: TArray<TOverrideCandidate>;
  const ATypo: string): TArray<TRuleFix>;
var
  Candidate: TOverrideCandidate;
  Fix: TRuleFix;
begin
  Result := nil;
  for Candidate in AVirtuals do
  begin
    if (FWildcards = nil) and (Result = nil) and SameText(Candidate.Symbol.Name, ATypo) and
      AdoptFix(Candidate, Fix) then
    begin
      Result := [Fix];
    end;
  end;
  if (Result = nil) and SameText(ATypo, 'Destroy') and (FMethod.Keyword = 'destructor') and
    AdoptFix(ObjectDestroy, Fix) then
  begin
    Result := [Fix];
  end;
end;

/// <summary>Kein gleichnamiger Kandidat: Tippfehler im Namen (Destory)?</summary>
procedure TOverrideTargetCheck.ReportTypo;
var
  Virtuals: TArray<TOverrideCandidate>;
  Typo: string;
begin
  Typo := TTextFuzzy.Closest(FMethod.Symbol.Name, TypoNames(Virtuals));
  if Typo = '' then
  begin
    FReport.Add(FMethod.Symbol.SelectionRange, cTexts[TInheritanceOverrideTargetsText.NoAncestor].Fmt(
      [FMethod.ClassName, FMethod.Symbol.Name]), TRuleConfidence.High);
    Exit;
  end;
  FReport.Add(FMethod.Symbol.SelectionRange,
    cTexts[TInheritanceOverrideTargetsText.NoAncestorMeant].Fmt([FMethod.ClassName, FMethod.Symbol.Name, Typo]),
    TRuleConfidence.High,
    TypoFixes(Virtuals, Typo));
end;

procedure TOverrideTargetCheck.CheckMethod(const AMethod: TMethodDecl);
var
  Done: Boolean;
begin
  Prepare(AMethod);
  Done := ReportTarget or (FObjectMissing and MatchText(AMethod.Symbol.Name, ObjectVirtualNames));
  Done := Done or not FComplete or ReportStatic or ReportOtherHead;
  if not Done then
  begin
    ReportTypo;
  end;
end;

/// <summary>E2353: Vorfahr mit sealed in der Signatur ("TBasis = class sealed").</summary>
procedure TOverrideTargetCheck.CheckSealed;
var
  Symbol: TIndexSymbol;
  Chain: TArray<TSymbolLocation>;
  Complete, ObjectMissing: Boolean;
begin
  for Symbol in FAncestry.Local.Symbols do
  begin
    if (Symbol.Kind <> TIndexSymbolKind.ClassType) or (Symbol.Container <> '') or (Symbol.Ancestors = nil) then
    begin
      Continue;
    end;
    Chain := FAncestry.Ancestors(Symbol.Name, Complete, ObjectMissing);
    if (Chain <> nil) and IsSealedSignature(Chain[0].Symbol.Signature) then
    begin
      FReport.Add(Symbol.SelectionRange, cTexts[TInheritanceOverrideTargetsText.Sealed].Fmt(
        [Chain[0].Symbol.Name]), TRuleConfidence.High);
    end;
  end;
end;

procedure TOverrideTargetCheck.Run;
var
  Method: TMethodDecl;
begin
  for Method in ClassMethods(FContext, FAncestry) do
  begin
    if Method.Has('override') then
    begin
      CheckMethod(Method);
    end;
  end;
  CheckSealed;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Inheritance.OverrideTargets', cTexts);

end.
