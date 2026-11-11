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
  Atlas.Common.Rules.Builtin.Naming,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.ClassActions,
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
  mText: string;
  mIndex, mDepth: Integer;
begin
  mText := Trim(ASignature);
  AKeyword := LowerCase(Copy(mText, 1, Pos(' ', mText + ' ') - 1));
  AHead := '';
  Result := MatchText(AKeyword, ['procedure', 'function', 'constructor', 'destructor']);
  if not Result then
  begin
    Exit;
  end;
  mText := Trim(Copy(mText, Length(AKeyword) + 1, MaxInt));
  mDepth := 0;
  for mIndex := 1 to Length(mText) do
    case mText[mIndex] of
      '(', '[':
        Inc(mDepth);
      ')', ']':
        Dec(mDepth);
      ';':
        if mDepth = 0 then
        begin
          AHead := Trim(Copy(mText, 1, mIndex - 1));
          Exit;
        end;
    end;
  AHead := mText;
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
  mIndex, mDepth: Integer;
  mSkipping: Boolean;
  mQuoted: Boolean;
begin
  Result := '';
  mDepth := 0;
  mSkipping := False;
  mQuoted := False;
  for mIndex := 1 to Length(AHead) do
  begin
    if AHead[mIndex] = '''' then
    begin
      mQuoted := not mQuoted;
    end;
    if not mQuoted then
    begin
      TrackDefault(AHead[mIndex], mDepth, mSkipping);
    end;
    if not mSkipping then
    begin
      Result := Result + AHead[mIndex];
    end;
  end;
  Result := StringReplace(Result, ' ;', ';', [rfReplaceAll]);
  Result := StringReplace(Result, ' )', ')', [rfReplaceAll]);
end;

/// <summary>Hängt die nicht leeren Typparameter aus ATypeParams ("T, U") an AList.</summary>
procedure AppendTypeParams(var AList: TArray<string>; const ATypeParams: string);
var
  mName: string;
begin
  for mName in SplitString(ATypeParams, ',') do
  begin
    if Trim(mName) <> '' then
    begin
      AList := AList + [Trim(mName)];
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
  mWords: TArray<string>;
  mIndex: Integer;
begin
  mWords := LowerCase(ASignature).Split([' ', '(', ')', '<', '>', '=', ';'], TStringSplitOptions.ExcludeEmpty);
  Result := False;
  mIndex := 0;
  while not Result and (mIndex < High(mWords)) do
  begin
    Result := (mWords[mIndex] = 'class') and ((mWords[mIndex + 1] = 'sealed') or ((mWords[mIndex + 1] = 'abstract') and
      (mIndex + 2 <= High(mWords)) and (mWords[mIndex + 2] = 'sealed')));
    Inc(mIndex);
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
  mCheck: TOverrideTargetCheck;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  mCheck := TOverrideTargetCheck.Create(AContext, AReport);
  try
    mCheck.Run;
  finally
    mCheck.Free;
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
  mLocation: TSymbolLocation;
  mSymbol: TIndexSymbol;
begin
  Result := nil;
  for mLocation in FChain do
  begin
    AppendTypeParams(Result, mLocation.Symbol.TypeParams);
  end;
  for mSymbol in FAncestry.Local.Symbols do
  begin
    if (mSymbol.Kind = TIndexSymbolKind.ClassType) and SameText(mSymbol.Name, FMethod.ClassName) then
    begin
      AppendTypeParams(Result, mSymbol.TypeParams);
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
  mIndex: Integer;
  mOwn, mOther: TArray<string>;
begin
  ACertain := True;
  if not SameShape(FMethod, ACandidate) then
  begin
    Exit(TOverrideMatch.Different);
  end;
  Result := TOverrideMatch.Same;
  mOwn := FMethod.Symbol.ParamTypes;
  mOther := ACandidate.Symbol.ParamTypes;
  for mIndex := 0 to High(mOwn) do
  begin
    if (mOwn[mIndex] = '') <> (mOther[mIndex] = '') then
    begin
      Exit(TOverrideMatch.Different);
    end;
    CompareType(mOwn[mIndex], mOther[mIndex], Result, ACertain);
  end;
  CompareType(FMethod.Symbol.TypeName, ACandidate.Symbol.TypeName, Result, ACertain);
end;

function TOverrideTargetCheck.Compare(const ACandidate: TOverrideCandidate): TOverrideMatch;
var
  mCertain: Boolean;
begin
  Result := CompareTypes(ACandidate, mCertain);
end;

/// <summary>Gleichnamige (AName leer: alle), im Nachfahren sichtbare Methoden der Vorfahren, der nächste zuerst.
/// </summary>
function TOverrideTargetCheck.Candidates(const AName: string): TArray<TOverrideCandidate>;
var
  mLocation: TSymbolLocation;
  mSymbol: TIndexSymbol;
  mItem: TOverrideCandidate;
begin
  Result := nil;
  for mLocation in FChain do
  begin
    for mSymbol in FAncestry.Methods(mLocation) do
    begin
      if CandidateOf(mLocation, mSymbol, AName, mItem) then
      begin
        Result := Result + [mItem];
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
  mDepth: Integer;
begin
  mDepth := 0;
  Result := AFrom;
  while (Result <= High(FTokens)) and ((mDepth <> 0) or not IsSymbolAt(Result, [';'])) do
  begin
    if IsSymbolAt(Result, ['(', '[']) then
    begin
      Inc(mDepth);
    end
    else if IsSymbolAt(Result, [')', ']']) then
    begin
      Dec(mDepth);
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
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 1 to High(FTokens) - 2 do
  begin
    if IsBodyHead(mIndex) then
    begin
      if Result >= 0 then
      begin
        Exit(-1);
      end;
      Result := mIndex - 1;
    end;
  end;
end;

/// <summary>Übernimmt Schlüsselwort und Kopf von ACandidate in Deklaration und, wenn eindeutig, Rumpf.</summary>
function TOverrideTargetCheck.AdoptFix(const ACandidate: TOverrideCandidate; out AFix: TRuleFix): Boolean;
var
  mFirst, mLast, mBody, mBodyLast: Integer;
  mEdits: TArray<TRuleEdit>;
begin
  AFix := Default(TRuleFix);
  mFirst := TokenIndex(FMethod.Header.StartOffset);
  mLast := -1;
  if mFirst >= 0 then
  begin
    mLast := HeadEnd(mFirst);
  end;
  Result := mLast > mFirst;
  if not Result then
  begin
    Exit;
  end;
  mEdits := [TRuleEdit.Create(TTextRange.Create(FTokens[mFirst].StartPos, FTokens[mLast].StartPos),
    ACandidate.Keyword + ' ' + ACandidate.Head)];
  mBody := BodyStart;
  mBodyLast := -1;
  if mBody > mLast then
  begin
    mBodyLast := HeadEnd(mBody);
  end;
  if mBodyLast > mBody then
  begin
    mEdits := mEdits + [TRuleEdit.Create(TTextRange.Create(FTokens[mBody].StartPos, FTokens[mBodyLast].StartPos),
      ACandidate.Keyword + ' ' + FMethod.ClassName + '.' + WithoutDefaults(ACandidate.Head))];
  end;
  AFix := TRuleFix.Create(cTexts[TInheritanceOverrideTargetsText.TakeSignature].Fmt([ACandidate.TypeName,
    ACandidate.Symbol.Name]),
    mEdits);
end;

/// <summary>Vorfahrenkette ab der Klasse, in deren Rumpf die Methode steht (#1326): THorseChannel&lt;T&gt; neben
/// THorseChannel; dazu Typparameter und gleichnamige Kandidaten.</summary>
procedure TOverrideTargetCheck.Prepare(const AMethod: TMethodDecl);
var
  mOwn: TSymbolLocation;
begin
  FMethod := AMethod;
  if FAncestry.OwnerOf(AMethod.Symbol, mOwn) then
  begin
    FChain := FAncestry.Ancestors(mOwn, FComplete, FObjectMissing);
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
  mCandidate: TOverrideCandidate;
begin
  Result := False;
  for mCandidate in FFound do
  begin
    if mCandidate.Symbol.IsVirtual and (Compare(mCandidate) = TOverrideMatch.Same) then
    begin
      if mCandidate.Symbol.HasDirective('final') then
      begin
        FReport.Add(FMethod.Symbol.SelectionRange,
          cTexts[TInheritanceOverrideTargetsText.Final].Fmt([mCandidate.TypeName, mCandidate.Symbol.Name]),
          TRuleConfidence.High);
      end;
      Exit(True);
    end;
  end;
end;

/// <summary>Gleicher Kopf, aber nicht virtuell (E2170).</summary>
function TOverrideTargetCheck.ReportStatic: Boolean;
var
  mCandidate: TOverrideCandidate;
begin
  Result := False;
  for mCandidate in FFound do
  begin
    if Compare(mCandidate) = TOverrideMatch.Same then
    begin
      FReport.Add(FMethod.Symbol.SelectionRange,
        cTexts[TInheritanceOverrideTargetsText.NotVirtual].Fmt([mCandidate.TypeName, mCandidate.Symbol.Name]),
        TRuleConfidence.High);
      Exit(True);
    end;
  end;
end;

/// <summary>Virtuelle Methode gleichen Namens mit anderem Kopf: die ähnlichste der nächsten Stufe.</summary>
function TOverrideTargetCheck.FindBest(out ABest: TBestCandidate): Boolean;
var
  mCandidate: TOverrideCandidate;
  mMatch: TOverrideMatch;
  mCertain: Boolean;
begin
  Result := False;
  ABest := Default(TBestCandidate);
  for mCandidate in FFound do
  begin
    if not mCandidate.Symbol.IsVirtual then
    begin
      Continue;
    end;
    mMatch := CompareTypes(mCandidate, mCertain);
    if not Result or (mMatch < ABest.Match) then
    begin
      ABest.Candidate := mCandidate;
      ABest.Match := mMatch;
      ABest.Certain := mCertain;
      Result := True;
    end;
  end;
end;

/// <summary>Meldet E2137 mit dem Kopf der ähnlichsten virtuellen Methode gleichen Namens.</summary>
function TOverrideTargetCheck.ReportOtherHead: Boolean;
var
  mBest: TBestCandidate;
  mConfidence: TRuleConfidence;
  mFixes: TArray<TRuleFix>;
  mFix: TRuleFix;
begin
  Result := FindBest(mBest);
  if not Result then
  begin
    Exit;
  end;
  mConfidence := TRuleConfidence.High;
  // Nur andere Typen: sicher nur, wenn keiner ein unbekannter Alias sein kann.
  if (mBest.Match = TOverrideMatch.OtherTypes) and not mBest.Certain then
  begin
    mConfidence := TRuleConfidence.Medium;
  end;
  mFixes := nil;
  if (FWildcards = nil) and AdoptFix(mBest.Candidate, mFix) then
  begin
    mFixes := [mFix];
  end;
  FReport.Add(FMethod.Symbol.SelectionRange, cTexts[TInheritanceOverrideTargetsText.OtherName].Fmt(
    [mBest.Candidate.TypeName, OwnHead(FMethod), mBest.Candidate.Head]), mConfidence, mFixes);
end;

/// <summary>Namen aller virtuellen Methoden gleicher Art der Vorfahren (dazu die von TObject, wenn System nicht im
/// Index steht); AVirtuals die zugehörigen Kandidaten.</summary>
function TOverrideTargetCheck.TypoNames(out AVirtuals: TArray<TOverrideCandidate>): TArray<string>;
var
  mCandidate: TOverrideCandidate;
  mName: string;
begin
  AVirtuals := nil;
  Result := nil;
  for mCandidate in Candidates('') do
  begin
    if mCandidate.Symbol.IsVirtual and (mCandidate.Keyword = FMethod.Keyword) then
    begin
      AVirtuals := AVirtuals + [mCandidate];
      Result := Result + [mCandidate.Symbol.Name];
    end;
  end;
  if FObjectMissing then
  begin
    for mName in cObjectVirtualNames do
    begin
      Result := Result + [mName];
    end;
  end;
end;

/// <summary>Korrektur auf den vermuteten Namen ATypo: Kopf des Kandidaten übernehmen, sonst TObject.Destroy.
/// </summary>
function TOverrideTargetCheck.TypoFixes(const AVirtuals: TArray<TOverrideCandidate>;
  const ATypo: string): TArray<TRuleFix>;
var
  mCandidate: TOverrideCandidate;
  mFix: TRuleFix;
begin
  Result := nil;
  for mCandidate in AVirtuals do
  begin
    if (FWildcards = nil) and (Result = nil) and SameText(mCandidate.Symbol.Name, ATypo) and
      AdoptFix(mCandidate, mFix) then
    begin
      Result := [mFix];
    end;
  end;
  if (Result = nil) and SameText(ATypo, 'Destroy') and (FMethod.Keyword = 'destructor') and
    AdoptFix(ObjectDestroy, mFix) then
  begin
    Result := [mFix];
  end;
end;

/// <summary>Kein gleichnamiger Kandidat: Tippfehler im Namen (Destory)?</summary>
procedure TOverrideTargetCheck.ReportTypo;
var
  mVirtuals: TArray<TOverrideCandidate>;
  mTypo: string;
begin
  mTypo := TTextFuzzy.Closest(FMethod.Symbol.Name, TypoNames(mVirtuals));
  if mTypo = '' then
  begin
    FReport.Add(FMethod.Symbol.SelectionRange, cTexts[TInheritanceOverrideTargetsText.NoAncestor].Fmt(
      [FMethod.ClassName, FMethod.Symbol.Name]), TRuleConfidence.High);
    Exit;
  end;
  FReport.Add(FMethod.Symbol.SelectionRange,
    cTexts[TInheritanceOverrideTargetsText.NoAncestorMeant].Fmt([FMethod.ClassName, FMethod.Symbol.Name, mTypo]),
    TRuleConfidence.High,
    TypoFixes(mVirtuals, mTypo));
end;

procedure TOverrideTargetCheck.CheckMethod(const AMethod: TMethodDecl);
var
  mDone: Boolean;
begin
  Prepare(AMethod);
  mDone := ReportTarget or (FObjectMissing and MatchText(AMethod.Symbol.Name, cObjectVirtualNames));
  mDone := mDone or not FComplete or ReportStatic or ReportOtherHead;
  if not mDone then
  begin
    ReportTypo;
  end;
end;

/// <summary>E2353: Vorfahr mit sealed in der Signatur ("TBasis = class sealed").</summary>
procedure TOverrideTargetCheck.CheckSealed;
var
  mSymbol: TIndexSymbol;
  mChain: TArray<TSymbolLocation>;
  mComplete, mObjectMissing: Boolean;
begin
  for mSymbol in FAncestry.Local.Symbols do
  begin
    if (mSymbol.Kind <> TIndexSymbolKind.ClassType) or (mSymbol.Container <> '') or (mSymbol.Ancestors = nil) then
    begin
      Continue;
    end;
    mChain := FAncestry.Ancestors(mSymbol.Name, mComplete, mObjectMissing);
    if (mChain <> nil) and IsSealedSignature(mChain[0].Symbol.Signature) then
    begin
      FReport.Add(mSymbol.SelectionRange, cTexts[TInheritanceOverrideTargetsText.Sealed].Fmt(
        [mChain[0].Symbol.Name]), TRuleConfidence.High);
    end;
  end;
end;

procedure TOverrideTargetCheck.Run;
var
  mMethod: TMethodDecl;
begin
  for mMethod in ClassMethods(FContext, FAncestry) do
  begin
    if mMethod.Has('override') then
    begin
      CheckMethod(mMethod);
    end;
  end;
  CheckSealed;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Inheritance.OverrideTargets', cTexts);

end.
