unit Atlas.Core.Debug.RunTo;

// Bis hier ausführen per Klick (#851), Kern ohne IDE:
// - CodeLine: Steht an einer Zeile ausführbarer Code? Näherung aus dem Text:
//   nur zwischen begin (bzw. asm) und end des Rumpfs einer Routine oder einer
//   lokalen Routine, ohne Leer- und Kommentarzeilen und ohne Zeilen, die nur
//   aus begin, end, try, finally, except, else, repeat, then oder do
//   bestehen. begin und end eines Rumpfs selbst zählen (dort setzt auch die
//   IDE ihre blauen Punkte).
// - Haltepunkte überspringen: ToDisable nennt die aktiven Haltepunkte außer
//   am Ziel. Was Atlas für einen Lauf ändert (Ziel angelegt oder
//   eingeschaltet, andere ausgeschaltet), hält TAtlasRunToState fest; als JSON
//   (ToJson/Parse) übersteht es einen Absturz der IDE und wird beim nächsten
//   Start zurückgesetzt.
// - Einmaliger Haltepunkt: gewöhnlicher Haltepunkt in der Gruppe cOnceGroup.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Editor.MethodToggle;

type
  /// <summary>Haltepunkt an Datei und Zeile (ab 0) mit seinem Aktiv-Zustand.</summary>
  TAtlasBreakpointState = record
    FileName: string;
    Line: Integer;
    Enabled: Boolean;
    class function Create(const AFileName: string; ALine: Integer; AEnabled: Boolean): TAtlasBreakpointState; static;
  end;

  TAtlasBreakpointStates = TArray<TAtlasBreakpointState>;

  /// <summary>Was Atlas für einen Lauf „bis hier“ geändert hat.</summary>
  TAtlasRunToState = record
    /// <summary>Ziel: Datei und Zeile (ab 0); '' ohne Lauf.</summary>
    FileName: string;
    Line: Integer;
    /// <summary>Hat Atlas den Haltepunkt am Ziel angelegt (sonst stand dort schon einer)?</summary>
    Created: Boolean;
    /// <summary>Geänderte Haltepunkte mit ihrem Zustand vorher.</summary>
    Changed: TAtlasBreakpointStates;
    function Active: Boolean;
  end;

  TAtlasRunTo = class
  public const
    /// <summary>Gruppe der einmaligen Haltepunkte (in der Haltepunktliste der IDE sichtbar).</summary>
    cOnceGroup = 'Atlas.Einmalig';
    cFormat = 1;
  public
    /// <summary>Ausführbarer Code an ALine (ab 0)? ALines: Zeilen des Textes, APlaces: seine Routinen.</summary>
    class function CodeLine(const ALines: TArray<string>; const APlaces: TArray<TAtlasMethodPlace>;
      ALine: Integer): Boolean; overload; static;
    class function CodeLine(const AText: string; ALine: Integer): Boolean; overload; static;
    /// <summary>Gleiche Stelle: Datei ohne Groß-/Kleinschreibung, gleiche Zeile.</summary>
    class function SamePlace(const AFileA: string; ALineA: Integer; const AFileB: string; ALineB: Integer): Boolean;
      static;
    /// <summary>Aktive Haltepunkte aus AStates außer an AFileName/ALine; ihr Zustand vorher ist Enabled.</summary>
    class function ToDisable(const AStates: TAtlasBreakpointStates; const AFileName: string;
      ALine: Integer): TAtlasBreakpointStates; static;
    /// <summary>AStates ohne die Einträge an den Stellen in ADone.</summary>
    class function Without(const AStates, ADone: TAtlasBreakpointStates): TAtlasBreakpointStates; static;
    class function ToJson(const AState: TAtlasRunToState): string; static;
    /// <summary>False bei fremdem Format oder ohne Ziel.</summary>
    class function Parse(const AJson: string; out AState: TAtlasRunToState): Boolean; static;
  end;

implementation

uses
  System.Math,
  System.Generics.Collections,
  Atlas.Text.Json,
  Atlas.Core.Editor.LineAnchor;

{ TAtlasBreakpointState }

class function TAtlasBreakpointState.Create(const AFileName: string; ALine: Integer;
  AEnabled: Boolean): TAtlasBreakpointState;
begin
  Result.FileName := AFileName;
  Result.Line := ALine;
  Result.Enabled := AEnabled;
end;

{ TAtlasRunToState }

function TAtlasRunToState.Active: Boolean;
begin
  Result := FileName <> '';
end;

{ Code ohne Kommentare }

type
  {$SCOPEDENUMS ON}
  TScanState = (Code, Brace, Paren);
  {$SCOPEDENUMS OFF}

function At(const ALine: string; AIndex: Integer; const APair: string): Boolean;
begin
  Result := Copy(ALine, AIndex, Length(APair)) = APair;
end;

/// <summary>Ende des offenen Blockkommentars ab AIndex suchen; AIndex steht danach dahinter bzw. hinter der Zeile.
/// </summary>
procedure SkipComment(const ALine: string; var AIndex: Integer; var AState: TScanState);
var
  mClose: string;
  mEnd: Integer;
begin
  mClose := '}';
  if AState = TScanState.Paren then
  begin
    mClose := '*)';
  end;
  mEnd := Pos(mClose, ALine, AIndex);
  if mEnd = 0 then
  begin
    AIndex := Length(ALine) + 1;
    Exit;
  end;
  AIndex := mEnd + Length(mClose);
  AState := TScanState.Code;
end;

/// <summary>String ab AIndex (auf dem Hochkomma) an AResult hängen; AIndex steht danach dahinter.</summary>
procedure TakeString(const ALine: string; var AIndex: Integer; var AResult: string);
var
  mEnd: Integer;
begin
  mEnd := Pos('''', ALine, AIndex + 1);
  if mEnd = 0 then
  begin
    mEnd := Length(ALine);
  end;
  AResult := AResult + Copy(ALine, AIndex, mEnd - AIndex + 1);
  AIndex := mEnd + 1;
end;

/// <summary>Code von ALine ohne Kommentare; AState trägt offene Blockkommentare in die nächste Zeile.</summary>
function StripComments(const ALine: string; var AState: TScanState): string;
var
  mIndex: Integer;
begin
  Result := '';
  mIndex := 1;
  while mIndex <= Length(ALine) do
  begin
    if AState <> TScanState.Code then
    begin
      SkipComment(ALine, mIndex, AState);
    end
    else if ALine[mIndex] = '''' then
    begin
      TakeString(ALine, mIndex, Result);
    end
    else if At(ALine, mIndex, '//') then
    begin
      Break;
    end
    else if At(ALine, mIndex, '(*') then
    begin
      AState := TScanState.Paren;
      Inc(mIndex, 2);
    end
    else
    begin
      if ALine[mIndex] = '{' then
      begin
        AState := TScanState.Brace;
      end
      else
      begin
        Result := Result + ALine[mIndex];
      end;
      Inc(mIndex);
    end;
  end;
  Result := Trim(Result);
end;

/// <summary>Nur ein Schlüsselwort ohne Anweisung (begin, end;, try …)?</summary>
function IsBareKeyword(const ACode: string): Boolean;
var
  mCode: string;
begin
  mCode := LowerCase(ACode);
  if mCode.EndsWith(';') then
  begin
    mCode := Trim(Copy(mCode, 1, Length(mCode) - 1));
  end;
  Result := (mCode = 'begin') or (mCode = 'end') or (mCode = 'try') or (mCode = 'finally') or (mCode = 'except') or
    (mCode = 'else') or (mCode = 'repeat') or (mCode = 'then') or (mCode = 'do') or (mCode = 'otherwise');
end;

/// <summary>Wörter von ACode (ohne Inhalt von Strings), klein.</summary>
function WordsOf(const ACode: string): TArray<string>;
var
  mIndex, mStart: Integer;
  mInString: Boolean;
begin
  Result := nil;
  mInString := False;
  mIndex := 1;
  while mIndex <= Length(ACode) do
  begin
    if ACode[mIndex] = '''' then
    begin
      mInString := not mInString;
      Inc(mIndex);
    end
    else if not mInString and CharInSet(ACode[mIndex], ['A'..'Z', 'a'..'z', '_']) and
      ((mIndex = 1) or not CharInSet(ACode[mIndex - 1], ['.', '&', '#', '$'])) then
    begin
      mStart := mIndex;
      while (mIndex <= Length(ACode)) and CharInSet(ACode[mIndex], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
      begin
        Inc(mIndex);
      end;
      Result := Result + [LowerCase(Copy(ACode, mStart, mIndex - mStart))];
    end
    else
    begin
      Inc(mIndex);
    end;
  end;
end;

type
  /// <summary>Blöcke beim Lesen einer Routine, Zeile für Zeile. Rümpfe öffnen begin und asm auf oberster Ebene
  /// (Routine und lokale Routinen); record, case und try zählen nur für die Tiefe.</summary>
  TBlockScan = record
    Depth: Integer;
    /// <summary>Zeile, in der der offene Rumpf begann; -1 außerhalb eines Rumpfs.</summary>
    Open: Integer;
    /// <summary>Hat die zuletzt gelesene Zeile einen Rumpf geöffnet oder geschlossen?</summary>
    Edge: Boolean;
    procedure Feed(const ACode: string; ALine: Integer);
  end;

procedure TBlockScan.Feed(const ACode: string; ALine: Integer);
var
  mWord: string;
begin
  Edge := False;
  for mWord in WordsOf(ACode) do
  begin
    if (mWord = 'begin') or (mWord = 'asm') or (mWord = 'try') or (mWord = 'case') or (mWord = 'record') then
    begin
      if (Depth = 0) and ((mWord = 'begin') or (mWord = 'asm')) then
      begin
        Open := ALine;
        Edge := True;
      end;
      Inc(Depth);
    end
    else if (mWord = 'end') and (Depth > 0) then
    begin
      Dec(Depth);
      Edge := Edge or ((Depth = 0) and (Open >= 0));
      if Depth = 0 then
      begin
        Open := -1;
      end;
    end;
  end;
end;

{ TAtlasRunTo }

class function TAtlasRunTo.CodeLine(const ALines: TArray<string>; const APlaces: TArray<TAtlasMethodPlace>;
  ALine: Integer): Boolean;
var
  mPlace: TAtlasMethodPlace;
  mState: TScanState;
  mScan: TBlockScan;
  mIndex: Integer;
  mCode: string;
  mInside: Boolean;
begin
  Result := False;
  if (ALine < 0) or (ALine > High(ALines)) or not TAtlasMethodToggle.BodyAt(APlaces, ALine, mPlace) then
  begin
    Exit;
  end;
  mState := TScanState.Code;
  mScan := Default(TBlockScan);
  mScan.Open := -1;
  mCode := '';
  mInside := False;
  for mIndex := mPlace.FirstLine + 1 to ALine do
  begin
    mCode := StripComments(ALines[mIndex], mState);
    mInside := mScan.Open >= 0;
    mScan.Feed(mCode, mIndex);
  end;
  Result := (mInside or mScan.Edge) and (mCode <> '') and (mScan.Edge or not IsBareKeyword(mCode));
end;

class function TAtlasRunTo.CodeLine(const AText: string; ALine: Integer): Boolean;
begin
  Result := CodeLine(TAtlasLineAnchors.Lines(AText), TAtlasMethodToggle.Places(AText), ALine);
end;

class function TAtlasRunTo.SamePlace(const AFileA: string; ALineA: Integer; const AFileB: string;
  ALineB: Integer): Boolean;
begin
  Result := SameText(AFileA, AFileB) and (ALineA = ALineB);
end;

class function TAtlasRunTo.ToDisable(const AStates: TAtlasBreakpointStates; const AFileName: string;
  ALine: Integer): TAtlasBreakpointStates;
var
  mState: TAtlasBreakpointState;
begin
  Result := nil;
  for mState in AStates do
  begin
    if mState.Enabled and not SamePlace(mState.FileName, mState.Line, AFileName, ALine) then
    begin
      Result := Result + [mState];
    end;
  end;
end;

class function TAtlasRunTo.Without(const AStates, ADone: TAtlasBreakpointStates): TAtlasBreakpointStates;
var
  mState, mDone: TAtlasBreakpointState;
  mFound: Boolean;
begin
  Result := nil;
  for mState in AStates do
  begin
    mFound := False;
    for mDone in ADone do
    begin
      mFound := mFound or SamePlace(mState.FileName, mState.Line, mDone.FileName, mDone.Line);
    end;
    if not mFound then
    begin
      Result := Result + [mState];
    end;
  end;
end;

function StateJson(const AState: TAtlasBreakpointState): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('file', AState.FileName);
  Result.AddPair('line', TJSONNumber.Create(AState.Line + 1));
  Result.AddPair('enabled', TJSONBool.Create(AState.Enabled));
end;

class function TAtlasRunTo.ToJson(const AState: TAtlasRunToState): string;
var
  mRoot: TJSONObject;
  mList: TJSONArray;
  mState: TAtlasBreakpointState;
begin
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('format', TJSONNumber.Create(cFormat));
    mRoot.AddPair('file', AState.FileName);
    mRoot.AddPair('line', TJSONNumber.Create(AState.Line + 1));
    mRoot.AddPair('created', TJSONBool.Create(AState.Created));
    mList := TJSONArray.Create;
    mRoot.AddPair('changed', mList);
    for mState in AState.Changed do
    begin
      mList.AddElement(StateJson(mState));
    end;
    Result := mRoot.ToJSON([]);
  finally
    mRoot.Free;
  end;
end;

/// <summary>Einträge von „changed“ in ARoot.</summary>
function ReadChanged(ARoot: TJSONObject): TAtlasBreakpointStates;
var
  mList: TJSONArray;
  mObject: TJSONObject;
  mIndex: Integer;
begin
  Result := nil;
  mList := TJsonRead.Items(ARoot, 'changed');
  if mList = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mList.Count - 1 do
  begin
    mObject := TJsonRead.AsObject(mList.Items[mIndex]);
    if (mObject <> nil) and (TJsonRead.Text(mObject, 'file') <> '') then
    begin
      Result := Result + [TAtlasBreakpointState.Create(TJsonRead.Text(mObject, 'file'),
        Max(0, TJsonRead.IntOr(mObject, 'line', 1) - 1), TJsonRead.FlagOr(mObject, 'enabled', True))];
    end;
  end;
end;

class function TAtlasRunTo.Parse(const AJson: string; out AState: TAtlasRunToState): Boolean;
var
  mValue: TJSONValue;
  mRoot: TJSONObject;
begin
  AState := Default(TAtlasRunToState);
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    mRoot := TJsonRead.AsObject(mValue);
    Result := (mRoot <> nil) and (TJsonRead.IntOr(mRoot, 'format', 0) = cFormat);
    if Result then
    begin
      AState.FileName := TJsonRead.Text(mRoot, 'file');
      AState.Line := Max(0, TJsonRead.IntOr(mRoot, 'line', 1) - 1);
      AState.Created := TJsonRead.FlagOr(mRoot, 'created', False);
      AState.Changed := ReadChanged(mRoot);
      Result := AState.Active;
    end;
  finally
    mValue.Free;
  end;
end;

end.
