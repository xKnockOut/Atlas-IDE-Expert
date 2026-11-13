unit Atlas.Core.Debug.Pins;

// Angeheftete Debug-Werte (#526), ohne VCL und Open Tools API:
//   - Ein Eintrag ist Projekt, Datei, Zeile (1-basiert) und Ausdruck. Je
//     Projekt höchstens cLimit; derselbe Ausdruck an derselben Zeile nur einmal.
//   - Die Einträge überdauern Debug-Sitzungen: gespeichert als JSON
//     {"format":1,"pins":[{"project","file","line","expression"}]}; die IDE-Seite
//     schreibt die Datei.
//   - Werte gelten je Halt. Ein Wert ist geändert, wenn sein Text sich vom
//     vorigen Halt unterscheidet (wie die Werte im Editor, #508). Das Ende der
//     Sitzung vergisst die Werte, nicht die Einträge.
//   - Ausgewertet wird ohne Nebenwirkungen (eseNone): Ausdrücke mit Aufrufen
//     bleiben ohne Wert.

interface

uses
  System.Generics.Collections,
  Atlas.Core.Debug.InlineValues;

type
  TAtlasDebugPin = record
    Project: string;
    FileName: string;
    /// <summary>Zeile im Editor, 1-basiert.</summary>
    Line: Integer;
    Expression: string;
    class function Create(const AProject, AFileName: string; ALine: Integer;
      const AExpression: string): TAtlasDebugPin; static;
    /// <summary>Schlüssel ohne Groß-/Kleinschreibung bei Projekt und Datei.</summary>
    function Key: string;
  end;

  TAtlasDebugPinList = TArray<TAtlasDebugPin>;

  TAtlasDebugPins = class
  public const
    cLimit = 100;
    cFormat = 1;
    /// <summary>Werte werden für die Anzeige auf so viele Zeichen gekürzt.</summary>
    cMaxText = 80;
  private
    FItems: TList<TAtlasDebugPin>;
    FValues: TDictionary<string, TAtlasInlineValueItem>;
    FPrevious: TDictionary<string, string>;
    function IndexOf(const APin: TAtlasDebugPin): Integer;
    function CountIn(const AProject: string): Integer;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>False, wenn es den Eintrag schon gibt, der Ausdruck leer ist oder das Projekt voll ist.</summary>
    function Add(const APin: TAtlasDebugPin): Boolean;
    function Remove(const APin: TAtlasDebugPin): Boolean;
    /// <summary>Einträge von AProject in AFileName, nach Zeile und Reihenfolge des Anheftens.</summary>
    function InFile(const AProject, AFileName: string): TAtlasDebugPinList;
    /// <summary>Alle Einträge von AProject in der Reihenfolge des Anheftens.</summary>
    function All(const AProject: string): TAtlasDebugPinList;
    function Count: Integer;
    function ToText: string;
    /// <summary>Liest ToText; False bei kaputtem Text (dann bleibt die Liste leer).</summary>
    function LoadFromText(const AText: string): Boolean;
    /// <summary>Neuer Halt: die Werte des vorigen merken, die aktuellen verwerfen.</summary>
    procedure NewStop;
    /// <summary>Ende der Sitzung: alle Werte vergessen.</summary>
    procedure EndSession;
    /// <summary>Wert von APin bei diesem Halt; AOk False = nicht auswertbar.</summary>
    procedure Put(const APin: TAtlasDebugPin; const AText: string; AOk: Boolean);
    /// <summary>Anzeige von APin: Name = Ausdruck, Text = Wert bzw. '' solange ausstehend.</summary>
    function ValueOf(const APin: TAtlasDebugPin): TAtlasInlineValueItem;
    /// <summary>Hat APin bei diesem Halt schon einen Wert (oder einen Fehler)?</summary>
    function Evaluated(const APin: TAtlasDebugPin): Boolean;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Text.Json,
  Atlas.Core.Hover.DebugValue;

{ TAtlasDebugPin }

class function TAtlasDebugPin.Create(const AProject, AFileName: string; ALine: Integer;
  const AExpression: string): TAtlasDebugPin;
begin
  Result.Project := AProject;
  Result.FileName := AFileName;
  Result.Line := ALine;
  Result.Expression := Trim(AExpression);
end;

function TAtlasDebugPin.Key: string;
begin
  Result := AnsiLowerCase(Project) + #0 + AnsiLowerCase(FileName) + #0 + IntToStr(Line) + #0 + Expression;
end;

{ TAtlasDebugPins }

constructor TAtlasDebugPins.Create;
begin
  inherited Create;
  FItems := TList<TAtlasDebugPin>.Create;
  FValues := TDictionary<string, TAtlasInlineValueItem>.Create;
  FPrevious := TDictionary<string, string>.Create;
end;

destructor TAtlasDebugPins.Destroy;
begin
  FreeAndNil(FPrevious);
  FreeAndNil(FValues);
  FreeAndNil(FItems);
  inherited Destroy;
end;

function TAtlasDebugPins.IndexOf(const APin: TAtlasDebugPin): Integer;
var
  mKey: string;
  mIndex: Integer;
begin
  Result := -1;
  mKey := APin.Key;
  for mIndex := 0 to FItems.Count - 1 do
  begin
    if FItems[mIndex].Key = mKey then
    begin
      Exit(mIndex);
    end;
  end;
end;

function TAtlasDebugPins.CountIn(const AProject: string): Integer;
var
  mPin: TAtlasDebugPin;
begin
  Result := 0;
  for mPin in FItems do
  begin
    if SameText(mPin.Project, AProject) then
    begin
      Inc(Result);
    end;
  end;
end;

function TAtlasDebugPins.Add(const APin: TAtlasDebugPin): Boolean;
begin
  Result := (APin.Expression <> '') and (APin.FileName <> '') and (APin.Line > 0) and (IndexOf(APin) < 0) and
    (CountIn(APin.Project) < cLimit);
  if Result then
  begin
    FItems.Add(APin);
  end;
end;

function TAtlasDebugPins.Remove(const APin: TAtlasDebugPin): Boolean;
var
  mIndex: Integer;
begin
  mIndex := IndexOf(APin);
  Result := mIndex >= 0;
  if Result then
  begin
    FItems.Delete(mIndex);
    FValues.Remove(APin.Key);
    FPrevious.Remove(APin.Key);
  end;
end;

function TAtlasDebugPins.InFile(const AProject, AFileName: string): TAtlasDebugPinList;
var
  mPin: TAtlasDebugPin;
  mLine, mCount: Integer;
  mLines: TList<Integer>;
begin
  // Nach Zeile, bei gleicher Zeile in der Reihenfolge des Anheftens (stabil ohne Sortierung).
  mLines := TList<Integer>.Create;
  try
    for mPin in FItems do
    begin
      if SameText(mPin.Project, AProject) and SameText(mPin.FileName, AFileName) and not mLines.Contains(mPin.Line)
        then
      begin
        mLines.Add(mPin.Line);
      end;
    end;
    mLines.Sort;
    SetLength(Result, FItems.Count);
    mCount := 0;
    for mLine in mLines do
    begin
      for mPin in FItems do
      begin
        if (mPin.Line = mLine) and SameText(mPin.Project, AProject) and SameText(mPin.FileName, AFileName) then
        begin
          Result[mCount] := mPin;
          Inc(mCount);
        end;
      end;
    end;
    SetLength(Result, mCount);
  finally
    mLines.Free;
  end;
end;

function TAtlasDebugPins.All(const AProject: string): TAtlasDebugPinList;
var
  mPin: TAtlasDebugPin;
  mCount: Integer;
begin
  SetLength(Result, FItems.Count);
  mCount := 0;
  for mPin in FItems do
  begin
    if SameText(mPin.Project, AProject) then
    begin
      Result[mCount] := mPin;
      Inc(mCount);
    end;
  end;
  SetLength(Result, mCount);
end;

function TAtlasDebugPins.Count: Integer;
begin
  Result := FItems.Count;
end;

function TAtlasDebugPins.ToText: string;
var
  mRoot, mItem: TJSONObject;
  mArray: TJSONArray;
  mPin: TAtlasDebugPin;
begin
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('format', TJSONNumber.Create(cFormat));
    mArray := TJSONArray.Create;
    mRoot.AddPair('pins', mArray);
    for mPin in FItems do
    begin
      mItem := TJSONObject.Create;
      mItem.AddPair('project', mPin.Project);
      mItem.AddPair('file', mPin.FileName);
      mItem.AddPair('line', TJSONNumber.Create(mPin.Line));
      mItem.AddPair('expression', mPin.Expression);
      mArray.AddElement(mItem);
    end;
    Result := mRoot.ToJSON([]);
  finally
    mRoot.Free;
  end;
end;

function TAtlasDebugPins.LoadFromText(const AText: string): Boolean;
var
  mJson: TJSONValue;
  mRoot: TJSONObject;
  mArray: TJSONArray;
  mIndex: Integer;
  mItem: TJSONObject;
begin
  FItems.Clear;
  FValues.Clear;
  FPrevious.Clear;
  mJson := TJSONObject.ParseJSONValue(AText);
  try
    mRoot := TJsonRead.AsObject(mJson);
    Result := (mRoot <> nil) and (TJsonRead.Int(mRoot, 'format') = cFormat);
    if not Result then
    begin
      Exit;
    end;
    mArray := TJsonRead.Items(mRoot, 'pins');
    if mArray = nil then
    begin
      Exit;
    end;
    for mIndex := 0 to mArray.Count - 1 do
    begin
      mItem := TJsonRead.AsObject(mArray.Items[mIndex]);
      if mItem <> nil then
      begin
        Add(TAtlasDebugPin.Create(TJsonRead.Text(mItem, 'project'), TJsonRead.Text(mItem, 'file'),
          TJsonRead.Int(mItem, 'line'), TJsonRead.Text(mItem, 'expression')));
      end;
    end;
  finally
    mJson.Free;
  end;
end;

procedure TAtlasDebugPins.NewStop;
var
  mPair: TPair<string, TAtlasInlineValueItem>;
begin
  for mPair in FValues do
  begin
    if mPair.Value.State = TAtlasInlineValueState.Ready then
    begin
      FPrevious.AddOrSetValue(mPair.Key, mPair.Value.Text);
    end;
  end;
  FValues.Clear;
end;

procedure TAtlasDebugPins.EndSession;
begin
  FValues.Clear;
  FPrevious.Clear;
end;

procedure TAtlasDebugPins.Put(const APin: TAtlasDebugPin; const AText: string; AOk: Boolean);
var
  mItem: TAtlasInlineValueItem;
  mPrevious: string;
begin
  mItem := Default(TAtlasInlineValueItem);
  mItem.Name := APin.Expression;
  if AOk then
  begin
    mItem.State := TAtlasInlineValueState.Ready;
    mItem.Text := TAtlasDebugExpression.Shorten(AText, cMaxText);
    mItem.Changed := FPrevious.TryGetValue(APin.Key, mPrevious) and (mPrevious <> mItem.Text);
  end
  else
  begin
    mItem.State := TAtlasInlineValueState.Failed;
    mItem.Text := '?';
  end;
  FValues.AddOrSetValue(APin.Key, mItem);
end;

function TAtlasDebugPins.ValueOf(const APin: TAtlasDebugPin): TAtlasInlineValueItem;
begin
  if not FValues.TryGetValue(APin.Key, Result) then
  begin
    Result := Default(TAtlasInlineValueItem);
    Result.Name := APin.Expression;
    Result.State := TAtlasInlineValueState.Pending;
    Result.Text := '…';
  end;
end;

function TAtlasDebugPins.Evaluated(const APin: TAtlasDebugPin): Boolean;
begin
  Result := FValues.ContainsKey(APin.Key);
end;

end.
