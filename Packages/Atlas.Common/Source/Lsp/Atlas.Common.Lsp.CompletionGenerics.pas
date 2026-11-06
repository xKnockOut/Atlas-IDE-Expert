unit Atlas.Common.Lsp.CompletionGenerics;

// Typargumente nach "<" eines generischen Typs (#450, ARG-051):
// - SiteAt erkennt an den Tokens vor dem Cursor "TObjectList<", "TDictionary<string, " usw. und zählt die
//   Kommas für den aktiven Typparameter (wie #436). Ob der Name davor wirklich ein generischer Typ ist, klärt
//   die Namensauflösung (Owner); "if A < B" bleibt so ein Vergleich.
// - Params liest die Typparameter samt Constraints aus der Deklaration ("TFoo<K; V: class, constructor>").
// - Apply behält nur Typen, die die Constraints erfüllen: class nur Klassen, record nur Records,
//   Aufzählungen und Grundtypen mit Wertsemantik, constructor nur Klassen mit parameterlosem Konstruktor, ein
//   Typ-Constraint nur Typen, die ihn implementieren bzw. davon abgeleitet sind. Jeder Eintrag trägt den
//   Typparameter, den Constraint, einen Code für die Erklärung (classes, values, constructible,
//   implements:IFoo, descends:TBasis) und die ausgeblendeten Arten (classes, records, interfaces, enums,
//   basic) für Überschrift und Fußzeile im Plugin. Grundtypen kommen dazu, wenn kein Constraint sie
//   ausschließt.

interface

uses
  System.SysUtils,
  System.Math,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.CompletionRequest;

type
  TGenericArgSite = record
    Found: Boolean;
    /// <summary>Position des Typnamens vor "&lt;".</summary>
    OwnerPosition: TTextPosition;
    /// <summary>Aktiver Typparameter, 0-basiert.</summary>
    Parameter: Integer;
  end;

  TGenericParam = record
    Name: string;
    /// <summary>Constraints wie im Quelltext, z. B. ['class', 'constructor'] oder ['IComparable'].</summary>
    Constraints: TArray<string>;
  end;

  /// <summary>Art eines Typarguments für die Constraints.</summary>
  TTypeArgKind = (Unknown, Class_, Record_, Interface_, Enum, Basic);

  TCompletionGenerics = class
  public const
    /// <summary>Grundtypen mit Wertsemantik (record-Constraint).</summary>
    cValueTypes: array[0..18] of string = ('Integer', 'Cardinal', 'Int64', 'UInt64', 'NativeInt', 'NativeUInt',
      'Byte', 'Word', 'ShortInt', 'SmallInt', 'Double', 'Single', 'Extended', 'Currency', 'Char', 'AnsiChar',
      'WideChar', 'Boolean', 'TDateTime');
    /// <summary>Weitere Grundtypen ohne Constraint.</summary>
    cOtherBasicTypes: array[0..2] of string = ('string', 'Variant', 'Pointer');
  public
    /// <summary>Offenes "&lt;" eines Typnamens vor dem Token ALast (das letzte vor dem angefangenen Namen).
    /// </summary>
    class function SiteAt(const ATokens: TArray<TPascalToken>; ALast: Integer): TGenericArgSite; static;
    /// <summary>Typparameter aus dem Kopf ab ALine/ACharacter (Name der Deklaration), z. B.
    /// "TFoo&lt;K; V: class&gt; = class"; leer ohne spitze Klammern.</summary>
    class function Params(const ALines: TArray<string>; ALine, ACharacter: Integer): TArray<TGenericParam>; static;
    /// <summary>Erklärungscode zu AConstraints: classes, values, constructible, implements:X, descends:X, ''.
    /// AInterface: der Typ-Constraint ist ein Interface.</summary>
    class function HintCode(const AConstraints: TArray<string>; AInterface: Boolean): string; static;
    /// <summary>Erfüllt ein Typ der Art AKind die Constraints? ASatisfiesType prüft einen Typ-Constraint,
    /// AConstructible den parameterlosen Konstruktor.</summary>
    class function Allowed(AKind: TTypeArgKind; const AConstraints: TArray<string>;
      const ASatisfiesType: TFunc<string, Boolean>; const AConstructible: TFunc<Boolean>): Boolean; static;
    /// <summary>Einträge nach den Constraints filtern und beschriften (siehe oben). AOwner ist der aufgelöste
    /// generische Typ, AParameter der aktive Typparameter.</summary>
    class function Apply(ARequest: TCompletionRequest; const AContext: TCompletionContext;
      const AOwner: TResolvedSymbol; const AItems: TArray<TCompletionItem>): TArray<TCompletionItem>; static;
    /// <summary>Symbol eines Eintrags über Datei und Namensposition aus dem Index, die eigene Unit aus dem Baum;
    /// AUnits merkt sich die Units je Datei. False ohne Quelle (Schlüsselwörter, Grundtypen).</summary>
    class function ItemSymbol(ARequest: TCompletionRequest; AUnits: TDictionary<string, TUnitIndex>;
      const AItem: TCompletionItem; out ASymbol: TResolvedSymbol): Boolean; static;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Common.Index.Files,
  Atlas.Common.Lsp.CompletionCollector,
  Atlas.Common.Lsp.FuzzyMatch;

const
  cMaxAncestorDepth = 32;

function IsTrivia(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive];
end;

function PreviousIndex(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex - 1;
  while (Result >= 0) and IsTrivia(ATokens[Result]) do
  begin
    Dec(Result);
  end;
end;

/// <summary>Name ohne Typargumente und ohne Unit davor: "Generics.IComparer&lt;T&gt;" → "IComparer".</summary>
function PlainName(const AName: string): string;
begin
  Result := Trim(AName);
  if Pos('<', Result) > 0 then
  begin
    Result := Copy(Result, 1, Pos('<', Result) - 1);
  end;
  Result := Copy(Result, LastDelimiter('.', Result) + 1, MaxInt);
end;

/// <summary>Kann AToken in einer Typargumentliste stehen: Namen, Punkte und string?</summary>
function IsTypeArgPart(const AToken: TPascalToken): Boolean;
begin
  Result := (AToken.Kind = TPascalTokenKind.Identifier) or AToken.IsSymbol('.') or AToken.IsKeyword('string');
end;

/// <summary>Stelle für das offene "&lt;" bei AOpen nach ACommas Kommas; gefunden nur hinter einem Namen.</summary>
function SiteOf(const ATokens: TArray<TPascalToken>; AOpen, ACommas: Integer): TGenericArgSite;
var
  mBefore: Integer;
begin
  Result := Default(TGenericArgSite);
  mBefore := PreviousIndex(ATokens, AOpen);
  if (mBefore >= 0) and (ATokens[mBefore].Kind = TPascalTokenKind.Identifier) then
  begin
    Result.Found := True;
    Result.OwnerPosition := ATokens[mBefore].StartPos;
    Result.Parameter := ACommas;
  end;
end;

{ TCompletionGenerics }

class function TCompletionGenerics.SiteAt(const ATokens: TArray<TPascalToken>; ALast: Integer): TGenericArgSite;
var
  mIndex, mDepth, mCommas: Integer;
begin
  Result := Default(TGenericArgSite);
  mDepth := 0;
  mCommas := 0;
  mIndex := ALast;
  if (mIndex >= 0) and IsTrivia(ATokens[mIndex]) then
  begin
    mIndex := PreviousIndex(ATokens, mIndex);
  end;
  while mIndex >= 0 do
  begin
    if ATokens[mIndex].IsSymbol('>') then
    begin
      Inc(mDepth);
    end
    else if ATokens[mIndex].IsSymbol('<') then
    begin
      if mDepth = 0 then
      begin
        Exit(SiteOf(ATokens, mIndex, mCommas));
      end;
      Dec(mDepth);
    end
    else if ATokens[mIndex].IsSymbol(',') then
    begin
      Inc(mCommas, IfThen(mDepth = 0, 1, 0));
    end
    else if not IsTypeArgPart(ATokens[mIndex]) then
    begin
      Exit;
    end;
    mIndex := PreviousIndex(ATokens, mIndex);
  end;
end;

/// <summary>Kopf ab dem Namen bis zur schließenden spitzen Klammer, auch über mehrere Zeilen.</summary>
function HeaderFrom(const ALines: TArray<string>; ALine, ACharacter: Integer): string;
var
  mLine: Integer;
begin
  Result := '';
  for mLine := ALine to Min(High(ALines), ALine + 20) do
  begin
    if mLine = ALine then
    begin
      Result := Result + Copy(ALines[mLine], ACharacter + 1, MaxInt);
    end
    else
    begin
      Result := Result + ' ' + ALines[mLine];
    end;
    if Pos('>', Result) > 0 then
    begin
      Break;
    end;
  end;
end;

/// <summary>Stelle des "&lt;" direkt hinter dem Namen; 0, wenn vorher etwas anderes steht oder es fehlt.</summary>
function AngleOpen(const AText: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 1 to Length(AText) do
  begin
    if AText[mIndex] = '<' then
    begin
      Exit(mIndex);
    end;
    if not CharInSet(AText[mIndex], ['A'..'Z', 'a'..'z', '0'..'9', '_', '.', ' ', #9]) then
    begin
      Break;
    end;
  end;
  Result := 0;
end;

/// <summary>Stelle der schließenden spitzen Klammer zu AOpen; 0 ohne.</summary>
function AngleClose(const AText: string; AOpen: Integer): Integer;
var
  mIndex, mDepth: Integer;
begin
  mDepth := 0;
  for mIndex := AOpen to Length(AText) do
  begin
    if AText[mIndex] = '<' then
    begin
      Inc(mDepth);
    end
    else if AText[mIndex] = '>' then
    begin
      Dec(mDepth);
      if mDepth = 0 then
      begin
        Exit(mIndex);
      end;
    end;
  end;
  Result := 0;
end;

/// <summary>Constraints "class, constructor" als Liste ohne leere Einträge.</summary>
function ConstraintList(const AText: string): TArray<string>;
var
  mConstraint: string;
begin
  Result := nil;
  for mConstraint in AText.Split([',']) do
  begin
    if Trim(mConstraint) <> '' then
    begin
      Result := Result + [Trim(mConstraint)];
    end;
  end;
end;

/// <summary>Die Typparameter einer Gruppe "K, V: class, constructor" an AParams anhängen.</summary>
procedure AddParamGroup(const AGroup: string; var AParams: TArray<TGenericParam>);
var
  mColon: Integer;
  mNames, mName: string;
  mConstraints: TArray<string>;
  mParam: TGenericParam;
begin
  mColon := Pos(':', AGroup);
  mNames := AGroup;
  mConstraints := nil;
  if mColon > 0 then
  begin
    mNames := Copy(AGroup, 1, mColon - 1);
    mConstraints := ConstraintList(Copy(AGroup, mColon + 1, MaxInt));
  end;
  for mName in mNames.Split([',']) do
  begin
    if Trim(mName) <> '' then
    begin
      mParam := Default(TGenericParam);
      mParam.Name := Trim(mName);
      mParam.Constraints := mConstraints;
      AParams := AParams + [mParam];
    end;
  end;
end;

class function TCompletionGenerics.Params(const ALines: TArray<string>; ALine,
  ACharacter: Integer): TArray<TGenericParam>;
var
  mText, mInner, mGroup: string;
  mOpen, mClose: Integer;
begin
  Result := nil;
  mText := HeaderFrom(ALines, ALine, ACharacter);
  mOpen := AngleOpen(mText);
  if mOpen = 0 then
  begin
    Exit;
  end;
  mClose := AngleClose(mText, mOpen);
  if mClose = 0 then
  begin
    Exit;
  end;
  mInner := Copy(mText, mOpen + 1, mClose - mOpen - 1);
  // Gruppen durch ";", darin "K, V: class, constructor".
  for mGroup in mInner.Split([';']) do
  begin
    AddParamGroup(mGroup, Result);
  end;
end;

/// <summary>Erklärung nach class bzw. record, in der Reihenfolge der Constraints; '' ohne.</summary>
function KindHint(const AConstraints: TArray<string>): string;
var
  mConstraint: string;
begin
  for mConstraint in AConstraints do
  begin
    if SameText(mConstraint, 'class') then
    begin
      Exit('classes');
    end;
    if SameText(mConstraint, 'record') then
    begin
      Exit('values');
    end;
  end;
  Result := '';
end;

class function TCompletionGenerics.HintCode(const AConstraints: TArray<string>; AInterface: Boolean): string;
begin
  if MatchText('constructor', AConstraints) then
  begin
    Result := 'constructible';
  end
  else
  begin
    Result := KindHint(AConstraints);
  end;
  if (Result <> '') or (Length(AConstraints) = 0) then
  begin
    Exit;
  end;
  if AInterface then
  begin
    Result := 'implements:' + AConstraints[0];
  end
  else
  begin
    Result := 'descends:' + AConstraints[0];
  end;
end;

class function TCompletionGenerics.Allowed(AKind: TTypeArgKind; const AConstraints: TArray<string>;
  const ASatisfiesType: TFunc<string, Boolean>; const AConstructible: TFunc<Boolean>): Boolean;
var
  mConstraint: string;
begin
  Result := True;
  for mConstraint in AConstraints do
  begin
    if SameText(mConstraint, 'class') then
    begin
      Result := Result and (AKind = TTypeArgKind.Class_);
    end
    else if SameText(mConstraint, 'record') then
    begin
      Result := Result and (AKind in [TTypeArgKind.Record_, TTypeArgKind.Enum, TTypeArgKind.Basic]);
    end
    else if SameText(mConstraint, 'constructor') then
    begin
      Result := Result and (AKind = TTypeArgKind.Class_) and AConstructible();
    end
    else
    begin
      // Typ-Constraint: Klassen, Interfaces (und Records bei Interfaces nicht) prüft die Namensauflösung.
      Result := Result and (AKind in [TTypeArgKind.Class_, TTypeArgKind.Interface_]) and ASatisfiesType(mConstraint);
    end;
  end;
end;

function KindOfSymbol(const ASymbol: TResolvedSymbol): TTypeArgKind;
begin
  case ASymbol.SymbolKind of
    TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType:
      Result := TTypeArgKind.Class_;
    TIndexSymbolKind.RecordType:
      Result := TTypeArgKind.Record_;
    TIndexSymbolKind.InterfaceType:
      Result := TTypeArgKind.Interface_;
    TIndexSymbolKind.EnumType:
      Result := TTypeArgKind.Enum;
  else
    Result := TTypeArgKind.Unknown;
  end;
end;

/// <summary>Code der Art für die Fußzeile („ausgeblendet: …“).</summary>
function KindCode(AKind: TTypeArgKind): string;
begin
  case AKind of
    TTypeArgKind.Class_:
      Result := 'classes';
    TTypeArgKind.Record_:
      Result := 'records';
    TTypeArgKind.Interface_:
      Result := 'interfaces';
    TTypeArgKind.Enum:
      Result := 'enums';
    TTypeArgKind.Basic:
      Result := 'basic';
  else
    Result := '';
  end;
end;

/// <summary>Führt die Kette des Interfaces AListed über seine Vorfahren zu AName?</summary>
function InterfaceChainHas(AResolver: TNameResolver; AListed: TResolvedSymbol; const AName: string): Boolean;
var
  mNext: TResolvedSymbol;
  mInner: Integer;
begin
  for mInner := 0 to cMaxAncestorDepth do
  begin
    if SameText(PlainName(AListed.Name), PlainName(AName)) then
    begin
      Exit(True);
    end;
    if not AResolver.AncestorOf(AListed, mNext) then
    begin
      Break;
    end;
    AListed := mNext;
  end;
  Result := False;
end;

/// <summary>Heißt der Vorfahr bzw. das Interface AAncestor von ACurrent AName, oder stammt es als Interface davon
/// ab (IFooEx = interface(IFoo))?</summary>
function AncestorSatisfies(AResolver: TNameResolver; const ACurrent: TResolvedSymbol;
  const AAncestor, AName: string): Boolean;
var
  mFromUnit: TUnitIndex;
  mListed: TResolvedSymbol;
begin
  Result := SameText(PlainName(AAncestor), PlainName(AName));
  if not Result and AResolver.DeclaringUnit(ACurrent, mFromUnit) and
    AResolver.ResolveTypeFrom(mFromUnit, AAncestor, mListed) and
    (mListed.SymbolKind = TIndexSymbolKind.InterfaceType) then
  begin
    Result := InterfaceChainHas(AResolver, mListed, AName);
  end;
end;

/// <summary>AType oder ein Vorfahr heißt AName oder listet es als Interface (auch über Vorfahren des Interfaces).
/// </summary>
function SatisfiesType(AResolver: TNameResolver; const AType: TResolvedSymbol; const AName: string): Boolean;
var
  mCurrent, mNext: TResolvedSymbol;
  mDepth: Integer;
  mAncestor: string;
begin
  Result := False;
  mCurrent := AType;
  for mDepth := 0 to cMaxAncestorDepth do
  begin
    if SameText(PlainName(mCurrent.Name), PlainName(AName)) then
    begin
      Exit(True);
    end;
    for mAncestor in mCurrent.Ancestors do
    begin
      if AncestorSatisfies(AResolver, mCurrent, mAncestor, AName) then
      begin
        Exit(True);
      end;
    end;
    if not AResolver.AncestorOf(mCurrent, mNext) then
    begin
      Exit;
    end;
    mCurrent := mNext;
  end;
end;

/// <summary>Klasse mit parameterlosem Konstruktor: der nächste deklarierte Create hat eine Variante ohne
/// Parameter; ohne eigenen gilt TObject.Create.</summary>
function Constructible(AResolver: TNameResolver; const AType: TResolvedSymbol): Boolean;
var
  mCtor: TResolvedSymbol;
  mParams: string;
begin
  if not AResolver.DeclaredMember(AType, 'Create', mCtor) or (mCtor.MinArgs = 0) then
  begin
    Exit(True);
  end;
  Result := False;
  for mParams in mCtor.VariantParams do
  begin
    if mParams = '' then
    begin
      Exit(True);
    end;
  end;
end;

class function TCompletionGenerics.ItemSymbol(ARequest: TCompletionRequest; AUnits: TDictionary<string, TUnitIndex>;
  const AItem: TCompletionItem; out ASymbol: TResolvedSymbol): Boolean;
var
  mUnitInfo: TUnitIndex;
  mSymbol: TIndexSymbol;
begin
  Result := False;
  ASymbol := Default(TResolvedSymbol);
  if AItem.SourceFile = '' then
  begin
    Exit;
  end;
  if not AUnits.TryGetValue(UpperCase(AItem.SourceFile), mUnitInfo) then
  begin
    // Die eigene Unit aus dem Baum, sie steht vielleicht noch nicht (aktuell) im Index.
    if SameText(AItem.SourceFile, ARequest.FileName) and (ARequest.Tree <> nil) then
    begin
      mUnitInfo := ARequest.UnitIndex;
    end
    else if (ARequest.Index = nil) or not TIndexFiles.UnitOf(ARequest.Index, AItem.SourceFile, mUnitInfo) then
    begin
      mUnitInfo := Default(TUnitIndex);
    end;
    AUnits.Add(UpperCase(AItem.SourceFile), mUnitInfo);
  end;
  for mSymbol in mUnitInfo.Symbols do
  begin
    if (mSymbol.SelectionRange.StartPos.Line = AItem.SourcePosition.Line) and
      (mSymbol.SelectionRange.StartPos.Character = AItem.SourcePosition.Character) and
      SameText(mSymbol.Name, AItem.Name) then
    begin
      ASymbol := TResolvedSymbol.FromIndex(mUnitInfo, mSymbol);
      Exit(True);
    end;
  end;
end;

/// <summary>Erfüllt ASymbol der Art AKind die Constraints, mit der Namensauflösung AResolver?</summary>
function ConstraintsAllow(AResolver: TNameResolver; AKind: TTypeArgKind; const AConstraints: TArray<string>;
  const ASymbol: TResolvedSymbol): Boolean;
var
  mSymbol: TResolvedSymbol;
  mLookup: TNameResolver;
begin
  // Eigene Kopien: anonyme Methoden fangen keine Parameter der umgebenden Routine.
  mSymbol := ASymbol;
  mLookup := AResolver;
  Result := TCompletionGenerics.Allowed(AKind, AConstraints,
    function(AName: string): Boolean
    begin
      Result := SatisfiesType(mLookup, mSymbol, AName);
    end,
    function: Boolean
    begin
      Result := Constructible(mLookup, mSymbol);
    end);
end;

type
  /// <summary>Filter und Beschriftung der Einträge für einen Typparameter (TCompletionGenerics.Apply).</summary>
  TGenericFilter = record
    Request: TCompletionRequest;
    Prefix: string;
    Param: TGenericParam;
    Code: string;
    Names: TDictionary<string, Boolean>;
    HiddenKinds: TList<string>;
    Kept: TList<TCompletionItem>;
    /// <summary>Erfüllt ein Typ der Art AKind die Constraints? Sonst merkt sich HiddenKinds die Art.</summary>
    function Admit(AKind: TTypeArgKind; const ASymbol: TResolvedSymbol): Boolean;
    /// <summary>AItem mit Typparameter, Constraint und Erklärung übernehmen.</summary>
    procedure Keep(const AItem: TCompletionItem);
    procedure AddItem(const AItem: TCompletionItem; AUnits: TDictionary<string, TUnitIndex>);
    procedure AddBasic(const AName: string);
  end;

function TGenericFilter.Admit(AKind: TTypeArgKind; const ASymbol: TResolvedSymbol): Boolean;
begin
  Result := ConstraintsAllow(Request.Resolver, AKind, Param.Constraints, ASymbol);
  if not Result and (KindCode(AKind) <> '') and not HiddenKinds.Contains(KindCode(AKind)) then
  begin
    HiddenKinds.Add(KindCode(AKind));
  end;
end;

procedure TGenericFilter.Keep(const AItem: TCompletionItem);
var
  mItem: TCompletionItem;
begin
  mItem := AItem;
  mItem.TypeParam := Param.Name;
  mItem.Constraint := string.Join(', ', Param.Constraints);
  mItem.ConstraintHint := Code;
  Kept.Add(mItem);
  Names.AddOrSetValue(UpperCase(AItem.Name), True);
end;

/// <summary>Art des Eintrags AItem aus dem Index, über Datei und Namensposition; Grundtypen ohne Quelle.</summary>
function ItemKind(ARequest: TCompletionRequest; AUnits: TDictionary<string, TUnitIndex>;
  const AItem: TCompletionItem; out AResolved: TResolvedSymbol): TTypeArgKind;
begin
  if TCompletionGenerics.ItemSymbol(ARequest, AUnits, AItem, AResolved) then
  begin
    Result := KindOfSymbol(AResolved);
  end
  else if MatchText(AItem.Name, TCompletionGenerics.cValueTypes) then
  begin
    Result := TTypeArgKind.Basic;
  end
  else
  begin
    Result := TTypeArgKind.Unknown;
  end;
end;

procedure TGenericFilter.AddItem(const AItem: TCompletionItem; AUnits: TDictionary<string, TUnitIndex>);
var
  mResolved: TResolvedSymbol;
  mKind: TTypeArgKind;
begin
  mKind := ItemKind(Request, AUnits, AItem, mResolved);
  // Unbekannte Art (Alias, Typparameter): nur ohne Constraint.
  if mKind = TTypeArgKind.Unknown then
  begin
    if Length(Param.Constraints) = 0 then
    begin
      Keep(AItem);
    end;
  end
  else if Admit(mKind, mResolved) then
  begin
    Keep(AItem);
  end;
end;

procedure TGenericFilter.AddBasic(const AName: string);
var
  mBasic: TCompletionItem;
begin
  if Names.ContainsKey(UpperCase(AName)) or (MatchScore(AName, Prefix, Request.Matching) = TFuzzyMatch.cNoMatch) or
    not Admit(TTypeArgKind.Basic, Default(TResolvedSymbol)) then
  begin
    Exit;
  end;
  mBasic := Default(TCompletionItem);
  mBasic.Name := AName;
  mBasic.Detail := 'System';
  mBasic.Kind := cKindStruct;
  Keep(mBasic);
end;

/// <summary>Typparameter von AOwner aus dem Quelltext; nicht lesbar die Namen aus dem Index, ohne Constraints.
/// </summary>
function ParamsOf(ARequest: TCompletionRequest; const AOwner: TResolvedSymbol): TArray<TGenericParam>;
var
  mText, mName: string;
  mParam: TGenericParam;
begin
  Result := nil;
  if SameText(AOwner.FileName, ARequest.FileName) then
  begin
    Result := TCompletionGenerics.Params(ARequest.Lines, AOwner.SelectionRange.StartPos.Line,
      AOwner.SelectionRange.StartPos.Character);
  end
  else if Assigned(ARequest.ReadText) and ARequest.ReadText(AOwner.FileName, mText) then
  begin
    // Ein #13 am Zeilenende stört Params nicht.
    Result := TCompletionGenerics.Params(mText.Split([#10]), AOwner.SelectionRange.StartPos.Line,
      AOwner.SelectionRange.StartPos.Character);
  end;
  if Length(Result) = 0 then
  begin
    for mName in AOwner.TypeParams.Split([',']) do
    begin
      mParam := Default(TGenericParam);
      mParam.Name := Trim(mName);
      Result := Result + [mParam];
    end;
  end;
end;

/// <summary>Ist der Typ-Constraint von AParam ein Interface („implementieren“, sonst „abgeleitet“)?</summary>
function IsInterfaceConstraint(AResolver: TNameResolver; const AOwner: TResolvedSymbol;
  const AParam: TGenericParam): Boolean;
var
  mUnitInfo: TUnitIndex;
  mConstraintType: TResolvedSymbol;
begin
  Result := (Length(AParam.Constraints) > 0) and AResolver.DeclaringUnit(AOwner, mUnitInfo) and
    AResolver.ResolveTypeFrom(mUnitInfo, AParam.Constraints[High(AParam.Constraints)], mConstraintType) and
    (mConstraintType.SymbolKind = TIndexSymbolKind.InterfaceType);
end;

class function TCompletionGenerics.Apply(ARequest: TCompletionRequest; const AContext: TCompletionContext;
  const AOwner: TResolvedSymbol; const AItems: TArray<TCompletionItem>): TArray<TCompletionItem>;
var
  mParams: TArray<TGenericParam>;
  mFilter: TGenericFilter;
  mUnits: TDictionary<string, TUnitIndex>;
  mItem: TCompletionItem;
  mName, mHidden: string;
  mIndex: Integer;
begin
  Result := AItems;
  mParams := ParamsOf(ARequest, AOwner);
  if (AContext.GenericParam < 0) or (AContext.GenericParam > High(mParams)) then
  begin
    Exit;
  end;
  mFilter := Default(TGenericFilter);
  mFilter.Request := ARequest;
  mFilter.Prefix := AContext.Prefix;
  mFilter.Param := mParams[AContext.GenericParam];
  mFilter.Code := HintCode(mFilter.Param.Constraints,
    IsInterfaceConstraint(ARequest.Resolver, AOwner, mFilter.Param));
  mUnits := TDictionary<string, TUnitIndex>.Create;
  mFilter.Names := TDictionary<string, Boolean>.Create;
  mFilter.HiddenKinds := TList<string>.Create;
  mFilter.Kept := TList<TCompletionItem>.Create;
  try
    for mItem in AItems do
    begin
      mFilter.AddItem(mItem, mUnits);
    end;
    for mName in cValueTypes do
    begin
      mFilter.AddBasic(mName);
    end;
    if Length(mFilter.Param.Constraints) = 0 then
    begin
      for mName in cOtherBasicTypes do
      begin
        mFilter.AddBasic(mName);
      end;
    end;
    mHidden := string.Join(',', mFilter.HiddenKinds.ToArray);
    Result := mFilter.Kept.ToArray;
    // Ausgeblendete Arten an jedem Eintrag; das Plugin liest sie am ersten.
    for mIndex := 0 to High(Result) do
    begin
      Result[mIndex].HiddenKinds := mHidden;
    end;
  finally
    mFilter.Kept.Free;
    mFilter.HiddenKinds.Free;
    mFilter.Names.Free;
    mUnits.Free;
  end;
end;

end.
