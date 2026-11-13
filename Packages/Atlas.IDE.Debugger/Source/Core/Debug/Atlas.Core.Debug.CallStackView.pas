unit Atlas.Core.Debug.CallStackView;

// Inhalt des Fensters „Aufrufstapel“ (#843), ohne VCL und Open Tools API:
//   - Rahmen mit Routine, Parametern (Atlas.Core.Debug.CallStackParams) und Unit:Zeile.
//   - Zeilen wie bei „Nur eigener Code“ (#578, TAtlasDebugOwnCode.Rows): Bibliotheksrahmen in Folge stehen als eine
//     zugeklappte Gruppe „7 Aufrufe in VCL“ mit der ersten und letzten Routine als Hinweis; aufgeklappte Gruppen
//     merkt sich das Fenster als Startindex.
//   - Suche nach Routine, Unit, Parametername oder -wert, ohne Groß/klein; Gruppen zählen ihre Treffer.
//   - Kopieren als Text (eine Zeile je Rahmen) oder Markdown (Liste mit `Unit.pas:Zeile`), wahlweise nur eigener
//     Code.
//   - Vergleich mit dem Stapel beim letzten Halt an derselben Stelle (TAtlasDebugStackHistory): Rahmen werden von
//     unten (Thread-Start) her verglichen; neue oder andere Rahmen und geänderte Parameter sind markiert.

interface

uses
  System.Generics.Collections,
  Atlas.Core.Debug.CallStack,
  Atlas.Core.Debug.OwnCode,
  Atlas.Core.Debug.CallStackParams;

type
  TAtlasDebugStackEntry = record
    Frame: TAtlasDebugFrame;
    Params: TAtlasCallStackParamList;
    /// <summary>Namen sind geklärt (Antwort des Servers da, oder es gibt nichts zu fragen).</summary>
    Named: Boolean;
    /// <summary>Neu oder eine andere Routine als beim letzten Halt.</summary>
    Changed: Boolean;
    function Routine: string;
    /// <summary>Unit des Rahmens: Dateiname ohne Pfad, ohne Quelltext der Unit-Teil der Routine.</summary>
    function UnitName: string;
    /// <summary>„Unit1.pas:42“; '' ohne Quelltext.</summary>
    function Location: string;
    /// <summary>Routine mit Parametern („Unit1.TForm1.Import(Anzahl = 5)“).</summary>
    function Text: string;
    /// <summary>Ein Parameter geändert?</summary>
    function ParamsChanged: Boolean;
  end;

  TAtlasDebugStackEntries = TArray<TAtlasDebugStackEntry>;

  TAtlasDebugStackView = record
  public
    Entries: TAtlasDebugStackEntries;
    class function FromFrames(const AFrames: TAtlasDebugFrames): TAtlasDebugStackView; static;
    function Count: Integer;
    function Frames: TAtlasDebugFrames;
    /// <summary>Stelle des Halts: Datei und Zeile des obersten Rahmens mit Quelltext; '' ohne.</summary>
    function Key: string;
    /// <summary>Zeilen der Anzeige; Bibliotheksrahmen gruppiert, AExpanded: aufgeklappte Gruppen.</summary>
    function Rows(const AExpanded: TArray<Integer>): TAtlasDebugStackRows;
    /// <summary>Trifft AQuery den Rahmen AIndex (Routine, Unit, Parameter)? Leere Suche trifft nichts.</summary>
    function Matches(AIndex: Integer; const AQuery: string): Boolean;
    /// <summary>Treffer unter den Rahmen der Zeile ARow.</summary>
    function Hits(const ARow: TAtlasDebugStackRow; const AQuery: string): Integer;
    /// <summary>Bibliothek einer Gruppe (VCL, RTL, FMX, Windows, …); '' bei gemischten Units.</summary>
    function Area(const ARow: TAtlasDebugStackRow): string;
    /// <summary>Erste und letzte Routine einer Gruppe („A … B“, bei einem Rahmen nur A).</summary>
    function Hint(const ARow: TAtlasDebugStackRow): string;
    /// <summary>Text zum Kopieren: AMarkdown als Liste mit `Unit.pas:Zeile`, AOwnOnly nur eigene Rahmen.</summary>
    function CopyText(AMarkdown, AOwnOnly: Boolean): string;
    /// <summary>Rahmen mit Quelltext, deren Parameter Atlas benennen soll: in sichtbaren Zeilen, noch ohne Namen.
    /// </summary>
    function Unnamed(const ARows: TAtlasDebugStackRows): TArray<Integer>;
    /// <summary>Markiert, was sich gegenüber APrevious geändert hat (von unten her verglichen).</summary>
    procedure CompareWith(const APrevious: TAtlasDebugStackView);
    /// <summary>Bibliothek zu einem Unit-Namen (Vcl.Controls → VCL, System.Classes → RTL).</summary>
    class function AreaOf(const AUnitName: string): string; static;
  end;

  /// <summary>Stapel beim letzten Halt je Stelle, höchstens cMaxKeys Stellen (die älteste fällt heraus).</summary>
  TAtlasDebugStackHistory = class
  public const
    cMaxKeys = 20;
  private
    FKeys: TList<string>;
    FStacks: TDictionary<string, TAtlasDebugStackView>;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Stapel zu seiner Stelle merken; ohne Stelle nichts.</summary>
    procedure Remember(const AStack: TAtlasDebugStackView);
    function Previous(const AKey: string; out AStack: TAtlasDebugStackView): Boolean;
    procedure Clear;
    function Count: Integer;
  end;

implementation

uses
  System.SysUtils;

{ TAtlasDebugStackEntry }

function TAtlasDebugStackEntry.Routine: string;
begin
  Result := Frame.Routine;
end;

function TAtlasDebugStackEntry.UnitName: string;
var
  mParts: TArray<string>;
  mIndex: Integer;
begin
  if Frame.FileName <> '' then
  begin
    // Windows- wie Linux-Trenner (die Tests laufen auch unter Linux).
    Exit(Copy(Frame.FileName, LastDelimiter('\/:', Frame.FileName) + 1, MaxInt));
  end;
  // Ohne Datei: der Teil der Routine vor dem ersten Typ (T…) bzw. vor dem letzten Namen.
  mParts := Routine.Split(['.']);
  Result := '';
  for mIndex := 0 to High(mParts) - 1 do
  begin
    if (Length(mParts[mIndex]) > 1) and (mParts[mIndex][1] = 'T') and CharInSet(mParts[mIndex][2], ['A'..'Z']) then
    begin
      Break;
    end;
    if Result <> '' then
    begin
      Result := Result + '.';
    end;
    Result := Result + mParts[mIndex];
  end;
end;

function TAtlasDebugStackEntry.Location: string;
begin
  Result := '';
  if Frame.HasSource then
  begin
    Result := UnitName + ':' + IntToStr(Frame.Line);
  end;
end;

function TAtlasDebugStackEntry.Text: string;
begin
  Result := Routine;
  if Params <> nil then
  begin
    Result := Result + '(' + TAtlasCallStackParams.ListText(Params) + ')';
  end;
end;

function TAtlasDebugStackEntry.ParamsChanged: Boolean;
var
  mParam: TAtlasCallStackParam;
begin
  for mParam in Params do
  begin
    if mParam.Changed then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

{ TAtlasDebugStackView }

class function TAtlasDebugStackView.FromFrames(const AFrames: TAtlasDebugFrames): TAtlasDebugStackView;
var
  mIndex: Integer;
begin
  SetLength(Result.Entries, Length(AFrames));
  for mIndex := 0 to High(AFrames) do
  begin
    Result.Entries[mIndex] := Default(TAtlasDebugStackEntry);
    Result.Entries[mIndex].Frame := AFrames[mIndex];
    Result.Entries[mIndex].Params := TAtlasCallStackParams.FromHeader(AFrames[mIndex].Header);
    // Ohne Quelltext oder ohne Werte gibt es nichts zu benennen.
    Result.Entries[mIndex].Named := not AFrames[mIndex].HasSource or (Result.Entries[mIndex].Params = nil);
  end;
end;

function TAtlasDebugStackView.Count: Integer;
begin
  Result := Length(Entries);
end;

function TAtlasDebugStackView.Frames: TAtlasDebugFrames;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(Entries));
  for mIndex := 0 to High(Entries) do
  begin
    Result[mIndex] := Entries[mIndex].Frame;
  end;
end;

function TAtlasDebugStackView.Key: string;
var
  mIndex: Integer;
begin
  mIndex := TAtlasDebugCallStack.FirstWithSource(Frames);
  Result := '';
  if mIndex >= 0 then
  begin
    Result := LowerCase(Entries[mIndex].Frame.FileName) + ':' + IntToStr(Entries[mIndex].Frame.Line);
  end;
end;

function TAtlasDebugStackView.Rows(const AExpanded: TArray<Integer>): TAtlasDebugStackRows;
begin
  Result := TAtlasDebugOwnCode.Rows(Frames, True, AExpanded);
end;

function TAtlasDebugStackView.Matches(AIndex: Integer; const AQuery: string): Boolean;
var
  mQuery: string;
  mParam: TAtlasCallStackParam;
begin
  Result := False;
  mQuery := LowerCase(Trim(AQuery));
  if (mQuery = '') or (AIndex < 0) or (AIndex > High(Entries)) then
  begin
    Exit;
  end;
  if LowerCase(Entries[AIndex].Routine).Contains(mQuery) or LowerCase(Entries[AIndex].UnitName).Contains(mQuery) then
  begin
    Exit(True);
  end;
  for mParam in Entries[AIndex].Params do
  begin
    if LowerCase(mParam.Name).Contains(mQuery) or LowerCase(mParam.Shown).Contains(mQuery) then
    begin
      Exit(True);
    end;
  end;
end;

function TAtlasDebugStackView.Hits(const ARow: TAtlasDebugStackRow; const AQuery: string): Integer;
var
  mIndex: Integer;
begin
  Result := 0;
  for mIndex := ARow.First to ARow.First + ARow.Count - 1 do
  begin
    if Matches(mIndex, AQuery) then
    begin
      Inc(Result);
    end;
  end;
end;

class function TAtlasDebugStackView.AreaOf(const AUnitName: string): string;
const
  cPrefixes: array[0..6] of string = ('Vcl', 'FMX', 'System', 'SysInit', 'Winapi', 'Data', 'Xml');
  cAreas: array[0..6] of string = ('VCL', 'FMX', 'RTL', 'RTL', 'Windows', 'Data', 'XML');
var
  mFirst: string;
  mIndex: Integer;
begin
  mFirst := AUnitName;
  if Pos('.', mFirst) > 0 then
  begin
    mFirst := Copy(mFirst, 1, Pos('.', mFirst) - 1);
  end;
  for mIndex := 0 to High(cPrefixes) do
  begin
    if SameText(mFirst, cPrefixes[mIndex]) then
    begin
      Exit(cAreas[mIndex]);
    end;
  end;
  Result := mFirst;
end;

function TAtlasDebugStackView.Area(const ARow: TAtlasDebugStackRow): string;
var
  mIndex: Integer;
  mArea: string;
begin
  Result := '';
  for mIndex := ARow.First to ARow.First + ARow.Count - 1 do
  begin
    mArea := AreaOf(ChangeFileExt(Entries[mIndex].UnitName, ''));
    if mIndex = ARow.First then
    begin
      Result := mArea;
    end
    else if not SameText(mArea, Result) then
    begin
      Exit('');
    end;
  end;
end;

function TAtlasDebugStackView.Hint(const ARow: TAtlasDebugStackRow): string;
begin
  Result := '';
  if ARow.Count <= 0 then
  begin
    Exit;
  end;
  Result := Entries[ARow.First].Routine;
  if ARow.Count > 1 then
  begin
    Result := Result + ' … ' + Entries[ARow.First + ARow.Count - 1].Routine;
  end;
end;

function TAtlasDebugStackView.CopyText(AMarkdown, AOwnOnly: Boolean): string;
var
  mLines: TArray<string>;
  mEntry: TAtlasDebugStackEntry;
  mLine: string;
begin
  mLines := nil;
  for mEntry in Entries do
  begin
    if AOwnOnly and not mEntry.Frame.Own then
    begin
      Continue;
    end;
    if AMarkdown then
    begin
      mLine := '- `' + mEntry.Text.Replace('`', '''') + '`';
      if mEntry.Location <> '' then
      begin
        mLine := mLine + ' – `' + mEntry.Location + '`';
      end;
    end
    else
    begin
      mLine := mEntry.Text;
      if mEntry.Location <> '' then
      begin
        mLine := mLine + '  ' + mEntry.Location;
      end;
    end;
    mLines := mLines + [mLine];
  end;
  Result := string.Join(sLineBreak, mLines);
end;

function TAtlasDebugStackView.Unnamed(const ARows: TAtlasDebugStackRows): TArray<Integer>;
var
  mRow: TAtlasDebugStackRow;
begin
  Result := nil;
  for mRow in ARows do
  begin
    if (mRow.Kind = TAtlasDebugStackRowKind.Frame) and not Entries[mRow.First].Named then
    begin
      Result := Result + [mRow.First];
    end;
  end;
end;

/// <summary>Vergleichswert eines Parameters: der ausgewertete Wert, wenn beide einen haben, sonst der der IDE.
/// </summary>
function SameParam(const A, B: TAtlasCallStackParam): Boolean;
begin
  if (A.Value <> '') and (B.Value <> '') then
  begin
    Result := A.Value = B.Value;
  end
  else
  begin
    Result := A.Raw = B.Raw;
  end;
end;

procedure TAtlasDebugStackView.CompareWith(const APrevious: TAtlasDebugStackView);
var
  mStep, mCurrent, mOld, mParam: Integer;
begin
  for mCurrent := 0 to High(Entries) do
  begin
    Entries[mCurrent].Changed := True;
    for mParam := 0 to High(Entries[mCurrent].Params) do
    begin
      Entries[mCurrent].Params[mParam].Changed := False;
    end;
  end;
  for mStep := 0 to Count - 1 do
  begin
    mCurrent := Count - 1 - mStep;
    mOld := APrevious.Count - 1 - mStep;
    if (mOld < 0) or not SameText(Entries[mCurrent].Routine, APrevious.Entries[mOld].Routine) then
    begin
      // Ab hier weichen die Stapel ab: Alles darüber ist neu.
      Break;
    end;
    Entries[mCurrent].Changed := False;
    for mParam := 0 to High(Entries[mCurrent].Params) do
    begin
      Entries[mCurrent].Params[mParam].Changed := (mParam > High(APrevious.Entries[mOld].Params)) or
        not SameParam(Entries[mCurrent].Params[mParam], APrevious.Entries[mOld].Params[mParam]);
    end;
  end;
end;

{ TAtlasDebugStackHistory }

constructor TAtlasDebugStackHistory.Create;
begin
  inherited Create;
  FKeys := TList<string>.Create;
  FStacks := TDictionary<string, TAtlasDebugStackView>.Create;
end;

destructor TAtlasDebugStackHistory.Destroy;
begin
  FreeAndNil(FStacks);
  FreeAndNil(FKeys);
  inherited Destroy;
end;

procedure TAtlasDebugStackHistory.Remember(const AStack: TAtlasDebugStackView);
var
  mKey: string;
begin
  mKey := AStack.Key;
  if mKey = '' then
  begin
    Exit;
  end;
  FKeys.Remove(mKey);
  FKeys.Add(mKey);
  FStacks.AddOrSetValue(mKey, AStack);
  while FKeys.Count > cMaxKeys do
  begin
    FStacks.Remove(FKeys[0]);
    FKeys.Delete(0);
  end;
end;

function TAtlasDebugStackHistory.Previous(const AKey: string; out AStack: TAtlasDebugStackView): Boolean;
begin
  AStack := Default(TAtlasDebugStackView);
  Result := (AKey <> '') and FStacks.TryGetValue(AKey, AStack);
end;

procedure TAtlasDebugStackHistory.Clear;
begin
  FKeys.Clear;
  FStacks.Clear;
end;

function TAtlasDebugStackHistory.Count: Integer;
begin
  Result := FKeys.Count;
end;

end.
