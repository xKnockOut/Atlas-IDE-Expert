unit Atlas.Core.Designer.PropertySearch;

// Formularweite Eigenschaftssuche (#524), ohne VCL und Windows:
// - Bedingungen als Text: „Font.Name = 'Tahoma'“, „Visible = False“,
//   „Klasse = TDBGrid“, „Caption enthält 'Kunde'“, „Hint gesetzt“,
//   „Hint nicht gesetzt“, „Tag <> 0“; mehrere mit „und“. Englisch ebenso
//   („Class“, „contains“, „is set“, „not set“, „and“). Vergleiche ohne
//   Groß-/Kleinschreibung; Strings der DFM ('a' + 'b', #13) als Text.
// - Suche über ein Formular und seine Vorfahren (Formularmodell aus dem
//   Designer oder der .dfm): Ein Wert, der nur in einem Vorfahrformular
//   steht, gilt und macht den Treffer „geerbt“.
// - AncestorOf liest die Vorfahrklasse aus dem Quelltext der Unit.

interface

uses
  Atlas.Core.Designer.FormModel;

type
  {$SCOPEDENUMS ON}
  TAtlasPropertyOp = (Equals, NotEquals, Contains, IsSet, NotSet);
  {$SCOPEDENUMS OFF}

  TAtlasPropertyCondition = record
    /// <summary>Pfad wie in der .dfm („Font.Name“); '' = die Klasse.</summary>
    Path: string;
    Op: TAtlasPropertyOp;
    /// <summary>Vergleichswert als Text (Strings ohne Hochkommas).</summary>
    Value: string;
  end;

  TAtlasPropertyQuery = record
    Conditions: TArray<TAtlasPropertyCondition>;
    /// <summary>Teil, der sich nicht lesen ließ; '' bei Erfolg.</summary>
    Invalid: string;
    class function Parse(const AText: string): TAtlasPropertyQuery; static;
    function Valid: Boolean;
  end;

  TAtlasPropertyHit = record
    Component: string;
    TypeName: string;
    /// <summary>Gefundene Werte („Font.Name = 'Tahoma'“), mit „; “ getrennt.</summary>
    Found: string;
    /// <summary>Mindestens ein Wert kommt aus einem Vorfahrformular.</summary>
    FromAncestor: Boolean;
  end;

  TAtlasPropertySearch = class
  public
    /// <summary>Treffer in einem Formular; AChain[0] ist das Formular, danach seine Vorfahren (Formularmodell).
    /// </summary>
    class function Search(const AQuery: TAtlasPropertyQuery;
      const AChain: TArray<TArray<TAtlasFormObject>>): TArray<TAtlasPropertyHit>; static;
    /// <summary>Vorfahrklasse von AClassName im Quelltext AUnitText („TfrmA = class(TfrmBasis)“); '' ohne.</summary>
    class function AncestorOf(const AUnitText, AClassName: string): string; static;
  end;

implementation

uses
  System.SysUtils;

const
  cClassWords: array[0..2] of string = ('klasse', 'class', 'classname');

{ Lesen }

/// <summary>Position von AWord (Kleinbuchstaben, mit Leerraum davor und danach) in AText außerhalb von
/// Hochkommas; 0 ohne.</summary>
function WordPos(const AText, AWord: string): Integer;
var
  mIndex: Integer;
  mQuoted: Boolean;
  mLower: string;
begin
  mLower := LowerCase(AText);
  mQuoted := False;
  for mIndex := 1 to Length(mLower) - Length(AWord) + 1 do
  begin
    if mLower[mIndex] = '''' then
    begin
      mQuoted := not mQuoted;
    end;
    if not mQuoted and (Copy(mLower, mIndex, Length(AWord)) = AWord) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := 0;
end;

/// <summary>AText an „ und “ bzw. „ and “ außerhalb von Hochkommas teilen.</summary>
function SplitAnd(const AText: string): TArray<string>;
const
  cGermanAnd = ' und ';
  cEnglishAnd = ' and ';
var
  mRest: string;
  mPos, mGerman, mEnglish, mLength: Integer;
begin
  Result := nil;
  mRest := AText;
  repeat
    mGerman := WordPos(mRest, cGermanAnd);
    mEnglish := WordPos(mRest, cEnglishAnd);
    mPos := mGerman;
    mLength := Length(cGermanAnd);
    if (mPos = 0) or ((mEnglish > 0) and (mEnglish < mPos)) then
    begin
      mPos := mEnglish;
      mLength := Length(cEnglishAnd);
    end;
    if mPos = 0 then
    begin
      Break;
    end;
    Result := Result + [Trim(Copy(mRest, 1, mPos - 1))];
    mRest := Copy(mRest, mPos + mLength, MaxInt);
  until False;
  Result := Result + [Trim(mRest)];
end;

function IsPathText(const AText: string): Boolean;
var
  mIndex: Integer;
begin
  Result := (AText <> '') and CharInSet(AText[1], ['A'..'Z', 'a'..'z', '_']);
  for mIndex := 2 to Length(AText) do
  begin
    Result := Result and CharInSet(AText[mIndex], ['A'..'Z', 'a'..'z', '_', '0'..'9', '.']);
  end;
end;

/// <summary>Vergleichswert: Strings der DFM als Text, sonst wie geschrieben.</summary>
function PlainValue(const AValue: string): string;
begin
  if not TAtlasFormModel.StringValue(AValue, Result) then
  begin
    Result := Trim(AValue);
  end;
end;

/// <summary>Pfad: '' bei „Klasse“, sonst der Pfad selbst; False, wenn es kein Pfad ist.</summary>
function PathOf(const AText: string; out APath: string): Boolean;
var
  mWord: string;
begin
  APath := Trim(AText);
  for mWord in cClassWords do
  begin
    if SameText(APath, mWord) then
    begin
      APath := '';
      Exit(True);
    end;
  end;
  Result := IsPathText(APath);
end;

/// <summary>„Pfad gesetzt“, „Pfad nicht gesetzt“ (auch „is set“, „not set“).</summary>
function SetCondition(const APart: string; out ACondition: TAtlasPropertyCondition): Boolean;
const
  cNot: array[0..2] of string = (' nicht gesetzt', ' not set', ' is not set');
  cSet: array[0..2] of string = (' gesetzt', ' is set', ' set');
var
  mLower, mSuffix: string;
begin
  mLower := LowerCase(APart);
  for mSuffix in cNot do
  begin
    if mLower.EndsWith(mSuffix) then
    begin
      ACondition.Op := TAtlasPropertyOp.NotSet;
      Exit(PathOf(Copy(APart, 1, Length(APart) - Length(mSuffix)), ACondition.Path));
    end;
  end;
  for mSuffix in cSet do
  begin
    if mLower.EndsWith(mSuffix) then
    begin
      ACondition.Op := TAtlasPropertyOp.IsSet;
      Exit(PathOf(Copy(APart, 1, Length(APart) - Length(mSuffix)), ACondition.Path));
    end;
  end;
  Result := False;
end;

/// <summary>„Pfad enthält Wert“, „Pfad &lt;&gt; Wert“, „Pfad = Wert“.</summary>
function CompareCondition(const APart: string; out ACondition: TAtlasPropertyCondition): Boolean;
var
  mPos, mLength: Integer;
begin
  mLength := Length(' enthält ');
  mPos := WordPos(APart, ' enthält ');
  if mPos = 0 then
  begin
    mPos := WordPos(APart, ' contains ');
    mLength := Length(' contains ');
  end;
  ACondition.Op := TAtlasPropertyOp.Contains;
  if mPos = 0 then
  begin
    mPos := WordPos(APart, '<>');
    mLength := 2;
    ACondition.Op := TAtlasPropertyOp.NotEquals;
  end;
  if mPos = 0 then
  begin
    mPos := WordPos(APart, '=');
    mLength := 1;
    ACondition.Op := TAtlasPropertyOp.Equals;
  end;
  ACondition.Value := PlainValue(Trim(Copy(APart, mPos + mLength, MaxInt)));
  Result := (mPos > 0) and (ACondition.Value <> '') and PathOf(Copy(APart, 1, mPos - 1), ACondition.Path);
end;

{ TAtlasPropertyQuery }

class function TAtlasPropertyQuery.Parse(const AText: string): TAtlasPropertyQuery;
var
  mPart: string;
  mCondition: TAtlasPropertyCondition;
begin
  Result := Default(TAtlasPropertyQuery);
  if Trim(AText) = '' then
  begin
    Result.Invalid := ' ';
    Exit;
  end;
  for mPart in SplitAnd(AText) do
  begin
    mCondition := Default(TAtlasPropertyCondition);
    if not (SetCondition(mPart, mCondition) or CompareCondition(mPart, mCondition)) then
    begin
      Result.Conditions := nil;
      Result.Invalid := mPart;
      if mPart = '' then
      begin
        Result.Invalid := ' ';
      end;
      Exit;
    end;
    Result.Conditions := Result.Conditions + [mCondition];
  end;
end;

function TAtlasPropertyQuery.Valid: Boolean;
begin
  Result := (Invalid = '') and (Length(Conditions) > 0);
end;

{ Suche }

type
  /// <summary>Komponente über die Vorfahrkette: je Ebene der Index im Formularmodell oder -1.</summary>
  TChainComponent = record
    Name: string;
    Indexes: TArray<Integer>;
  end;

/// <summary>Index des Objekts zu AName in AObjects; beim Formular selbst (AIsRoot) das erste Objekt.</summary>
function IndexIn(const AObjects: TArray<TAtlasFormObject>; const AName: string; AIsRoot: Boolean): Integer;
begin
  Result := -1;
  if AIsRoot then
  begin
    if Length(AObjects) > 0 then
    begin
      Result := 0;
    end;
    Exit;
  end;
  Result := TAtlasFormModel.IndexOf(AObjects, AName);
  if Result = 0 then
  begin
    // Das Formular selbst heißt in jeder Ebene anders; ein gleichnamiges Kind gibt es nicht.
    Result := -1;
  end;
end;

function Known(const AComponents: TArray<TChainComponent>; const AName: string): Boolean;
var
  mComponent: TChainComponent;
begin
  for mComponent in AComponents do
  begin
    if SameText(mComponent.Name, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Alle Komponenten der Kette: zuerst das Formular, dann die der Vorfahren, dann neue.</summary>
function ChainComponents(const AChain: TArray<TArray<TAtlasFormObject>>): TArray<TChainComponent>;
var
  mLevel, mIndex, mObject: Integer;
  mItem: TChainComponent;
begin
  Result := nil;
  for mLevel := High(AChain) downto 0 do
  begin
    for mObject := 0 to High(AChain[mLevel]) do
    begin
      mItem := Default(TChainComponent);
      mItem.Name := AChain[mLevel][mObject].Name;
      if mObject = 0 then
      begin
        mItem.Name := AChain[0][0].Name;
      end;
      if (mItem.Name = '') or Known(Result, mItem.Name) then
      begin
        Continue;
      end;
      SetLength(mItem.Indexes, Length(AChain));
      for mIndex := 0 to High(AChain) do
      begin
        mItem.Indexes[mIndex] := IndexIn(AChain[mIndex], mItem.Name, mObject = 0);
      end;
      Result := Result + [mItem];
    end;
  end;
end;

/// <summary>Wert von APath (Eigenschaft oder Ereignis) im Objekt.</summary>
function ObjectValue(const AObject: TAtlasFormObject; const APath: string; out AValue: string): Boolean;
var
  mEvent: TAtlasFormValue;
begin
  Result := AObject.ValueOf(APath, AValue);
  if Result then
  begin
    Exit;
  end;
  for mEvent in AObject.Events do
  begin
    if SameText(mEvent.Path, APath) then
    begin
      AValue := mEvent.Value;
      Exit(True);
    end;
  end;
end;

/// <summary>Wert über die Kette, der nächste gewinnt; ALevel = Ebene, aus der er kommt.</summary>
function ChainValue(const AChain: TArray<TArray<TAtlasFormObject>>; const AComponent: TChainComponent;
  const APath: string; out AValue: string; out ALevel: Integer): Boolean;
var
  mLevel: Integer;
begin
  for mLevel := 0 to High(AChain) do
  begin
    if (AComponent.Indexes[mLevel] >= 0) and
      ObjectValue(AChain[mLevel][AComponent.Indexes[mLevel]], APath, AValue) then
    begin
      ALevel := mLevel;
      Exit(True);
    end;
  end;
  AValue := '';
  ALevel := 0;
  Result := False;
end;

function ChainClass(const AChain: TArray<TArray<TAtlasFormObject>>; const AComponent: TChainComponent;
  out ALevel: Integer): string;
var
  mLevel: Integer;
begin
  for mLevel := 0 to High(AChain) do
  begin
    if AComponent.Indexes[mLevel] >= 0 then
    begin
      ALevel := mLevel;
      Exit(AChain[mLevel][AComponent.Indexes[mLevel]].TypeName);
    end;
  end;
  ALevel := 0;
  Result := '';
end;

/// <summary>Erfüllt der Wert die Bedingung?</summary>
function Meets(const ACondition: TAtlasPropertyCondition; AHas: Boolean; const AValue: string): Boolean;
begin
  case ACondition.Op of
    TAtlasPropertyOp.IsSet:
      Result := AHas;
    TAtlasPropertyOp.NotSet:
      Result := not AHas;
    TAtlasPropertyOp.Contains:
      Result := AHas and (Pos(LowerCase(ACondition.Value), LowerCase(PlainValue(AValue))) > 0);
    TAtlasPropertyOp.NotEquals:
      Result := AHas and not SameText(PlainValue(AValue), ACondition.Value);
  else
    Result := AHas and SameText(PlainValue(AValue), ACondition.Value);
  end;
end;

/// <summary>Treffer für eine Komponente der Kette; False, wenn eine Bedingung nicht passt.</summary>
function Check(const AQuery: TAtlasPropertyQuery; const AChain: TArray<TArray<TAtlasFormObject>>;
  const AComponent: TChainComponent; out AHit: TAtlasPropertyHit): Boolean;
var
  mCondition: TAtlasPropertyCondition;
  mValue: string;
  mLevel, mClassLevel: Integer;
  mHas: Boolean;
begin
  AHit := Default(TAtlasPropertyHit);
  AHit.Component := AComponent.Name;
  AHit.TypeName := ChainClass(AChain, AComponent, mClassLevel);
  for mCondition in AQuery.Conditions do
  begin
    if mCondition.Path = '' then
    begin
      mHas := AHit.TypeName <> '';
      mValue := AHit.TypeName;
      mLevel := 0;
    end
    else
    begin
      mHas := ChainValue(AChain, AComponent, mCondition.Path, mValue, mLevel);
    end;
    if not Meets(mCondition, mHas, mValue) then
    begin
      Exit(False);
    end;
    if mHas and (mCondition.Path <> '') then
    begin
      if AHit.Found <> '' then
      begin
        AHit.Found := AHit.Found + '; ';
      end;
      AHit.Found := AHit.Found + TAtlasFormValue.Create(mCondition.Path, mValue).Text;
      AHit.FromAncestor := AHit.FromAncestor or (mLevel > 0);
    end;
  end;
  // Nur im Vorfahren vorhanden: auch die Komponente selbst ist geerbt.
  AHit.FromAncestor := AHit.FromAncestor or ((Length(AComponent.Indexes) > 0) and (AComponent.Indexes[0] < 0));
  Result := True;
end;

class function TAtlasPropertySearch.Search(const AQuery: TAtlasPropertyQuery;
  const AChain: TArray<TArray<TAtlasFormObject>>): TArray<TAtlasPropertyHit>;
var
  mComponent: TChainComponent;
  mHit: TAtlasPropertyHit;
begin
  Result := nil;
  if not AQuery.Valid or (Length(AChain) = 0) or (Length(AChain[0]) = 0) then
  begin
    Exit;
  end;
  for mComponent in ChainComponents(AChain) do
  begin
    if Check(AQuery, AChain, mComponent, mHit) then
    begin
      Result := Result + [mHit];
    end;
  end;
end;

{ Vorfahr }

/// <summary>Bezeichner ab APos nach Leerraum; APos danach dahinter.</summary>
function NextWord(const AText: string; var APos: Integer): string;
var
  mStart: Integer;
begin
  while (APos <= Length(AText)) and CharInSet(AText[APos], [' ', #9, #13, #10]) do
  begin
    Inc(APos);
  end;
  mStart := APos;
  while (APos <= Length(AText)) and CharInSet(AText[APos], ['A'..'Z', 'a'..'z', '_', '0'..'9', '.']) do
  begin
    Inc(APos);
  end;
  if APos = mStart then
  begin
    Result := Copy(AText, APos, 1);
    Inc(APos);
    Exit;
  end;
  Result := Copy(AText, mStart, APos - mStart);
end;

class function TAtlasPropertySearch.AncestorOf(const AUnitText, AClassName: string): string;
var
  mLower, mName: string;
  mFrom, mFound, mPos: Integer;
begin
  Result := '';
  if AClassName = '' then
  begin
    Exit;
  end;
  mLower := LowerCase(AUnitText);
  mName := LowerCase(AClassName);
  mFrom := 1;
  repeat
    mFound := Pos(mName, mLower, mFrom);
    if mFound = 0 then
    begin
      Exit;
    end;
    mFrom := mFound + Length(mName);
    // Ganzes Wort, dann „= class(“.
    if (mFound > 1) and CharInSet(mLower[mFound - 1], ['a'..'z', '_', '0'..'9']) then
    begin
      Continue;
    end;
    mPos := mFrom;
    if (NextWord(mLower, mPos) = '=') and (NextWord(mLower, mPos) = 'class') and (NextWord(mLower, mPos) = '(') then
    begin
      mFound := mPos;
      Result := NextWord(AUnitText, mFound);
      Exit;
    end;
  until False;
end;

end.
