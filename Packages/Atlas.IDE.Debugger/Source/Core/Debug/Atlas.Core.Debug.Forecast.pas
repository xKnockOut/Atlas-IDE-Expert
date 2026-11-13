unit Atlas.Core.Debug.Forecast;

// Bedingungen vorausschauen (#2169), ohne VCL und Open Tools API:
//   - Antwort des Servers (atlas.server.upcomingConditions) lesen: die
//     kommenden if, while und case derselben Routine, deren Bedingung sich aus
//     dem jetzigen Zustand ergibt, mit Teilausdrücken und Zweigen.
//   - Auswerten über TAtlasWhyHere (#1878): Werte und Vergleiche ohne Aufruf,
//     Kurzschluss bei and/or. Aufrufe und Getter gibt die Vorhersage nie frei;
//     eine Bedingung, die nur mit einem Aufruf entschieden wäre, bleibt offen.
//   - Zweig: if True = then, False = else (oder keiner); while False = keiner;
//     case: Wert des Selektors gegen die Werte der Marken (Bereiche nur bei
//     Zahlen), ohne Treffer else (oder keiner). Offen = keine Vorhersage.
//   - Text am Ende der Kopfzeile: „⟨= False · FOnline⟩“ (der entscheidende
//     Teil einer and/or-Verknüpfung), bei case „⟨→ smManual⟩“.
//   - Blass: Zeilen der Zweige, die nicht drankommen, außer der Kopfzeile und
//     Zeilen, die auch zum gewählten Zweig gehören.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Debug.WhyHere;

type
  TAtlasForecastBranch = record
    /// <summary>then, else, body oder item.</summary>
    Name: string;
    /// <summary>Erste und letzte Zeile (ab 0).</summary>
    FromLine: Integer;
    ToLine: Integer;
    /// <summary>Nur bei item: je Marke Index des Teils für Anfang und Ende (-1 ohne Bereich).</summary>
    Labels: TArray<TArray<Integer>>;
    function Holds(ALine: Integer): Boolean;
  end;

  TAtlasForecastBranches = TArray<TAtlasForecastBranch>;

  /// <summary>Wörter der Anzeige, von der Oberfläche in der Sprache der IDE.</summary>
  TAtlasForecastTexts = record
    /// <summary>case ohne Treffer mit else („else-Zweig“).</summary>
    ElseBranch: string;
    /// <summary>case ohne Treffer und ohne else („kein Zweig“).</summary>
    NoBranch: string;
  end;

  TAtlasForecast = class
  public const
    cCommand = 'atlas.server.upcomingConditions';
    /// <summary>Taken: noch offen bzw. nicht vorhersagbar.</summary>
    cUnknown = -1;
    /// <summary>Taken: kein Zweig läuft (if ohne else bei False, while bei False, case ohne Treffer).</summary>
    cNone = -2;
  private
    FWhy: TAtlasWhyHere;
    FBranches: TArray<TAtlasForecastBranches>;
    function BranchIndex(ABlock: Integer; const AName: string): Integer;
    function KnownValue(ABlock, APart: Integer; out AValue: string): Boolean;
    function MatchesLabel(ABlock: Integer; const ASelector: string; const ALabel: TArray<Integer>;
      out AKnown: Boolean): Boolean;
    function CaseTaken(ABlock: Integer): Integer;
    function Decisive(ABlock: Integer): string;
    function LabelText(ABlock, ABranch: Integer): string;
    function BlockText(ABlock: Integer; const ATexts: TAtlasForecastTexts): string;
    function ConditionText(ABlock: Integer): string;
    function CaseText(ABlock: Integer; const ATexts: TAtlasForecastTexts): string;
    function SkippedIn(ABlock, ALine: Integer): Boolean;
    class function ReadBranch(AItem: TJSONObject): TAtlasForecastBranch; static;
    class function ReadBranches(AItem: TJSONObject): TAtlasForecastBranches; static;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Argumente des Befehls als JSON: [uri, line, lines].</summary>
    class function Arguments(const AUri: string; ALine, ALines: Integer): string; static;
    /// <summary>Antwort des Servers lesen; je Block seine Zweige an derselben Stelle in ABranches. False ohne
    /// format 1 bzw. bei leerem oder kaputtem Text.</summary>
    class function ReadAnswerText(const AText: string; out ABlocks: TAtlasWhyHereBlocks;
      out ABranches: TArray<TAtlasForecastBranches>): Boolean; static;
    /// <summary>Neuer Halt in AFileName.</summary>
    procedure Start(const AFileName: string; const ABlocks: TAtlasWhyHereBlocks;
      const ABranches: TArray<TAtlasForecastBranches>);
    procedure Clear;
    function Active: Boolean;
    /// <summary>Nächster Teil zum Auswerten, nie ein Aufruf; False, wenn nichts mehr aussteht.</summary>
    function NextPending(out ARef: TAtlasWhyHereRef): Boolean;
    procedure Put(const ARef: TAtlasWhyHereRef; const AValue: string; AOk: Boolean);
    /// <summary>Index des Zweigs, der drankommt, oder cUnknown bzw. cNone.</summary>
    function Taken(ABlock: Integer): Integer;
    /// <summary>Text am Ende der Zeile ALine (ab 0); '' ohne Vorhersage dort.</summary>
    function LineText(const AFileName: string; ALine: Integer; const ATexts: TAtlasForecastTexts): string;
    /// <summary>Liegt ALine nur in Zweigen, die nach der Vorhersage übersprungen werden?</summary>
    function Dimmed(const AFileName: string; ALine: Integer): Boolean;
    property Why: TAtlasWhyHere read FWhy;
  end;

implementation

uses
  Atlas.Text.Json;

const
  cOpen = '⟨';
  cClose = '⟩';
  cDot = ' · ';
  cArrow = '→ ';
  cIsTrue = '= True';
  cIsFalse = '= False';
  /// <summary>Länge eines Zeichens in Hochkommas: 'a'.</summary>
  cQuotedCharLength = 3;

{ TAtlasForecastBranch }

function TAtlasForecastBranch.Holds(ALine: Integer): Boolean;
begin
  Result := (FromLine <= ALine) and (ALine <= ToLine);
end;

{ TAtlasForecast }

constructor TAtlasForecast.Create;
begin
  inherited Create;
  FWhy := TAtlasWhyHere.Create;
end;

destructor TAtlasForecast.Destroy;
begin
  FreeAndNil(FWhy);
  FBranches := nil;
  inherited Destroy;
end;

class function TAtlasForecast.Arguments(const AUri: string; ALine, ALines: Integer): string;
begin
  // Gleicher Aufbau wie bei „Warum bin ich hier?“: [uri, line, Zahl].
  Result := TAtlasWhyHere.Arguments(AUri, ALine, ALines);
end;

function IntItem(AItems: TJSONArray; AIndex: Integer): Integer;
begin
  Result := -1;
  if AItems.Items[AIndex] is TJSONNumber then
  begin
    Result := TJSONNumber(AItems.Items[AIndex]).AsInt;
  end;
end;

class function TAtlasForecast.ReadBranch(AItem: TJSONObject): TAtlasForecastBranch;
var
  mLabels, mPair: TJSONValue;
  mLabel: TArray<Integer>;
begin
  Result := Default(TAtlasForecastBranch);
  Result.Name := TJsonRead.Text(AItem, 'name');
  Result.FromLine := TJsonRead.IntOr(AItem, 'from', -1);
  Result.ToLine := TJsonRead.IntOr(AItem, 'to', -1);
  mLabels := AItem.GetValue('labels');
  if not (mLabels is TJSONArray) then
  begin
    Exit;
  end;
  for mPair in TJSONArray(mLabels) do
  begin
    if (mPair is TJSONArray) and (TJSONArray(mPair).Count = 2) then
    begin
      mLabel := TArray<Integer>.Create(IntItem(TJSONArray(mPair), 0), IntItem(TJSONArray(mPair), 1));
      Result.Labels := Result.Labels + [mLabel];
    end;
  end;
end;

class function TAtlasForecast.ReadBranches(AItem: TJSONObject): TAtlasForecastBranches;
var
  mBranches, mItem: TJSONValue;
begin
  Result := nil;
  mBranches := AItem.GetValue('branches');
  if not (mBranches is TJSONArray) then
  begin
    Exit;
  end;
  for mItem in TJSONArray(mBranches) do
  begin
    if mItem is TJSONObject then
    begin
      Result := Result + [ReadBranch(TJSONObject(mItem))];
    end;
  end;
end;

class function TAtlasForecast.ReadAnswerText(const AText: string; out ABlocks: TAtlasWhyHereBlocks;
  out ABranches: TArray<TAtlasForecastBranches>): Boolean;
var
  mJson, mBlocks, mItem: TJSONValue;
  mBlock: TAtlasWhyHereBlock;
begin
  ABlocks := nil;
  ABranches := nil;
  Result := False;
  if AText = '' then
  begin
    Exit;
  end;
  mJson := TJSONObject.ParseJSONValue(AText);
  try
    Result := (mJson is TJSONObject) and (TJsonRead.IntOr(TJSONObject(mJson), 'format', 0) = 1);
    if not Result then
    begin
      Exit;
    end;
    mBlocks := TJSONObject(mJson).GetValue('blocks');
    if not (mBlocks is TJSONArray) then
    begin
      Exit;
    end;
    for mItem in TJSONArray(mBlocks) do
    begin
      if not (mItem is TJSONObject) then
      begin
        Continue;
      end;
      mBlock := TAtlasWhyHere.ReadBlock(TJSONObject(mItem));
      if ((mBlock.Kind = 'if') or (mBlock.Kind = 'while') or (mBlock.Kind = 'case')) and (mBlock.Line >= 0) and
        (Length(mBlock.Parts) > 0) then
      begin
        ABlocks := ABlocks + [mBlock];
        ABranches := ABranches + [ReadBranches(TJSONObject(mItem))];
      end;
    end;
  finally
    mJson.Free;
  end;
end;

procedure TAtlasForecast.Start(const AFileName: string; const ABlocks: TAtlasWhyHereBlocks;
  const ABranches: TArray<TAtlasForecastBranches>);
begin
  FWhy.Start(AFileName, ABlocks);
  FBranches := Copy(ABranches);
  SetLength(FBranches, Length(ABlocks));
end;

procedure TAtlasForecast.Clear;
begin
  FWhy.Clear;
  FBranches := nil;
end;

function TAtlasForecast.Active: Boolean;
begin
  Result := FWhy.Active;
end;

function TAtlasForecast.NextPending(out ARef: TAtlasWhyHereRef): Boolean;
begin
  // Aufrufe gibt die Vorhersage nie frei (AllowCalls): TAtlasWhyHere liefert sie dann nicht.
  Result := FWhy.NextPending(ARef);
end;

procedure TAtlasForecast.Put(const ARef: TAtlasWhyHereRef; const AValue: string; AOk: Boolean);
begin
  FWhy.Put(ARef, AValue, AOk);
end;

function TAtlasForecast.BranchIndex(ABlock: Integer; const AName: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(FBranches[ABlock]) do
  begin
    if FBranches[ABlock][mIndex].Name = AName then
    begin
      Exit(mIndex);
    end;
  end;
  Result := cNone;
end;

function TAtlasForecast.KnownValue(ABlock, APart: Integer; out AValue: string): Boolean;
begin
  AValue := '';
  Result := (APart >= 0) and (APart <= High(FWhy.Blocks[ABlock].Parts)) and
    (FWhy.Blocks[ABlock].Parts[APart].State = TAtlasWhyHereState.Value);
  if Result then
  begin
    AValue := Trim(FWhy.Blocks[ABlock].Parts[APart].Value);
  end;
end;

/// <summary>Ordnungszahl eines Werts: ganze Zahl oder ein Zeichen in Hochkommas ('a').</summary>
function OrdinalOf(const AValue: string; out AOrdinal: Int64): Boolean;
begin
  Result := TryStrToInt64(AValue, AOrdinal);
  if not Result and (Length(AValue) = cQuotedCharLength) and (AValue[1] = '''') and
    (AValue[cQuotedCharLength] = '''') then
  begin
    AOrdinal := Ord(AValue[2]);
    Result := True;
  end;
end;

function TAtlasForecast.MatchesLabel(ABlock: Integer; const ASelector: string; const ALabel: TArray<Integer>;
  out AKnown: Boolean): Boolean;
var
  mLow, mHigh: string;
  mSelector, mFrom, mTo: Int64;
begin
  Result := False;
  AKnown := KnownValue(ABlock, ALabel[0], mLow);
  if not AKnown then
  begin
    Exit;
  end;
  if ALabel[1] < 0 then
  begin
    if OrdinalOf(ASelector, mSelector) and OrdinalOf(mLow, mFrom) then
    begin
      Exit(mSelector = mFrom);
    end;
    Exit(SameText(ASelector, mLow));
  end;
  // Bereiche nur bei Zahlen und Zeichen; bei Aufzählungen kennt Atlas die Reihenfolge nicht.
  AKnown := KnownValue(ABlock, ALabel[1], mHigh) and OrdinalOf(ASelector, mSelector) and OrdinalOf(mLow, mFrom) and
    OrdinalOf(mHigh, mTo);
  Result := AKnown and (mFrom <= mSelector) and (mSelector <= mTo);
end;

function TAtlasForecast.CaseTaken(ABlock: Integer): Integer;
var
  mSelector: string;
  mBranch: Integer;
  mLabel: TArray<Integer>;
  mKnown: Boolean;
begin
  if not KnownValue(ABlock, 0, mSelector) then
  begin
    Exit(cUnknown);
  end;
  for mBranch := 0 to High(FBranches[ABlock]) do
  begin
    for mLabel in FBranches[ABlock][mBranch].Labels do
    begin
      if MatchesLabel(ABlock, mSelector, mLabel, mKnown) then
      begin
        Exit(mBranch);
      end;
      // Eine Marke ohne Wert könnte passen: dann lieber keine Vorhersage.
      if not mKnown then
      begin
        Exit(cUnknown);
      end;
    end;
  end;
  Result := BranchIndex(ABlock, 'else');
end;

function TAtlasForecast.Taken(ABlock: Integer): Integer;
var
  mKind: string;
begin
  Result := cUnknown;
  if (ABlock < 0) or (ABlock > High(FWhy.Blocks)) then
  begin
    Exit;
  end;
  mKind := FWhy.Blocks[ABlock].Kind;
  if mKind = 'case' then
  begin
    Exit(CaseTaken(ABlock));
  end;
  case FWhy.Truth(ABlock, 0) of
    TAtlasWhyHereTruth.IsTrue:
      Result := 0;
    TAtlasWhyHereTruth.IsFalse:
      if mKind = 'if' then
      begin
        Result := BranchIndex(ABlock, 'else');
      end
      else
      begin
        Result := cNone;
      end;
  end;
end;

function TAtlasForecast.Decisive(ABlock: Integer): string;
var
  mRoot: TAtlasWhyHerePart;
  mTruth, mDecides: TAtlasWhyHereTruth;
  mChild: Integer;
begin
  // Bei and entscheidet der erste False-Teil, bei or der erste True-Teil.
  Result := '';
  mRoot := FWhy.Blocks[ABlock].Parts[0];
  mTruth := FWhy.Truth(ABlock, 0);
  if mRoot.Kind = 'and' then
  begin
    mDecides := TAtlasWhyHereTruth.IsFalse;
  end
  else if mRoot.Kind = 'or' then
  begin
    mDecides := TAtlasWhyHereTruth.IsTrue;
  end
  else
  begin
    Exit;
  end;
  if mTruth <> mDecides then
  begin
    Exit;
  end;
  for mChild in FWhy.ChildrenOf(ABlock, 0) do
  begin
    if FWhy.Truth(ABlock, mChild) = mDecides then
    begin
      Exit(Trim(FWhy.Blocks[ABlock].Parts[mChild].Text));
    end;
  end;
end;

function TAtlasForecast.ConditionText(ABlock: Integer): string;
var
  mDecisive: string;
begin
  case FWhy.Truth(ABlock, 0) of
    TAtlasWhyHereTruth.IsTrue:
      Result := cIsTrue;
    TAtlasWhyHereTruth.IsFalse:
      Result := cIsFalse;
  else
    Exit('');
  end;
  mDecisive := Decisive(ABlock);
  if mDecisive <> '' then
  begin
    Result := Result + cDot + mDecisive;
  end;
end;

function TAtlasForecast.LabelText(ABlock, ABranch: Integer): string;
var
  mLabel: TArray<Integer>;
  mTexts: TArray<string>;
  mText: string;
begin
  mTexts := nil;
  for mLabel in FBranches[ABlock][ABranch].Labels do
  begin
    mText := Trim(FWhy.Blocks[ABlock].Parts[mLabel[0]].Text);
    if mLabel[1] >= 0 then
    begin
      mText := mText + '..' + Trim(FWhy.Blocks[ABlock].Parts[mLabel[1]].Text);
    end;
    mTexts := mTexts + [mText];
  end;
  Result := string.Join(', ', mTexts);
end;

function TAtlasForecast.CaseText(ABlock: Integer; const ATexts: TAtlasForecastTexts): string;
var
  mTaken: Integer;
begin
  mTaken := CaseTaken(ABlock);
  if mTaken = cUnknown then
  begin
    Result := '';
  end
  else if mTaken = cNone then
  begin
    Result := cArrow + ATexts.NoBranch;
  end
  else if FBranches[ABlock][mTaken].Name = 'else' then
  begin
    Result := cArrow + ATexts.ElseBranch;
  end
  else
  begin
    Result := cArrow + LabelText(ABlock, mTaken);
  end;
end;

function TAtlasForecast.BlockText(ABlock: Integer; const ATexts: TAtlasForecastTexts): string;
begin
  if FWhy.Blocks[ABlock].Kind = 'case' then
  begin
    Result := CaseText(ABlock, ATexts);
  end
  else
  begin
    Result := ConditionText(ABlock);
  end;
  if Result <> '' then
  begin
    Result := cOpen + Result + cClose;
  end;
end;

function TAtlasForecast.LineText(const AFileName: string; ALine: Integer; const ATexts: TAtlasForecastTexts): string;
var
  mBlock: Integer;
  mText: string;
  mTexts: TArray<string>;
begin
  Result := '';
  if not Active or not SameText(AFileName, FWhy.FileName) then
  begin
    Exit;
  end;
  mTexts := nil;
  for mBlock := 0 to High(FWhy.Blocks) do
  begin
    if FWhy.Blocks[mBlock].Line = ALine then
    begin
      mText := BlockText(mBlock, ATexts);
      if mText <> '' then
      begin
        mTexts := mTexts + [mText];
      end;
    end;
  end;
  Result := string.Join('  ', mTexts);
end;

function TAtlasForecast.SkippedIn(ABlock, ALine: Integer): Boolean;
var
  mTaken, mBranch: Integer;
begin
  Result := False;
  mTaken := Taken(ABlock);
  // Offen: nichts blass. Die Kopfzeile und Zeilen des gewählten Zweigs bleiben normal.
  if (mTaken = cUnknown) or (ALine = FWhy.Blocks[ABlock].Line) or
    ((mTaken >= 0) and FBranches[ABlock][mTaken].Holds(ALine)) then
  begin
    Exit;
  end;
  for mBranch := 0 to High(FBranches[ABlock]) do
  begin
    if (mBranch <> mTaken) and FBranches[ABlock][mBranch].Holds(ALine) then
    begin
      Exit(True);
    end;
  end;
end;

function TAtlasForecast.Dimmed(const AFileName: string; ALine: Integer): Boolean;
var
  mBlock: Integer;
begin
  Result := False;
  if not Active or not SameText(AFileName, FWhy.FileName) then
  begin
    Exit;
  end;
  for mBlock := 0 to High(FWhy.Blocks) do
  begin
    if SkippedIn(mBlock, ALine) then
    begin
      Exit(True);
    end;
  end;
end;

end.
