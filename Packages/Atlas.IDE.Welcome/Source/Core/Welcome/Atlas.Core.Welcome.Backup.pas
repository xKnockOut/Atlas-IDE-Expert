unit Atlas.Core.Welcome.Backup;

// Sicherung des Willkommensseiten-Layouts der IDE (#753), ohne Windows:
// Der Registry-Schlüssel der IDE (HKCU\Software\Embarcadero\BDS\<Version>\
// WelcomePage) samt Unterschlüsseln und allen Werten mit Typ als JSON, vor
// „Atlas-Layout anwenden“. „Atlas-Layout zurücksetzen“ und TAtlasWelcomeRetire
// (Atlas auf der Willkommensseite der IDE aus, #1114, #761) schreiben ihn exakt
// zurück (auch: Schlüssel fehlte vorher → wieder löschen), und die Marke für
// den gewünschten Stand nutzt dasselbe Format. Den Zugriff auf die Registry liefert die IDE-Schicht über
// IAtlasRegistryAccess; TAtlasMemoryRegistry dient Tests und Vergleichen.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Welcome.Contract;

type
  TAtlasRegKind = Atlas.Core.Welcome.Contract.TAtlasRegKind;
  TAtlasRegValue = Atlas.Core.Welcome.Contract.TAtlasRegValue;

  /// <summary>Ein Registry-Schlüssel mit Werten und Unterschlüsseln.</summary>
  TAtlasRegKey = class
  private
    FName: string;
    FValues: TList<TAtlasRegValue>;
    FKeys: TObjectList<TAtlasRegKey>;
  public
    constructor Create(const AName: string);
    destructor Destroy; override;
    function AddKey(const AName: string): TAtlasRegKey;
    function FindKey(const AName: string): TAtlasRegKey;
    procedure SetValue(const AValue: TAtlasRegValue);
    function FindValue(const AName: string; out AValue: TAtlasRegValue): Boolean;
    function Clone: TAtlasRegKey;
    /// <summary>Gleiche Werte (Name, Typ, Inhalt) und Unterschlüssel, Reihenfolge egal, Namen ohne
    /// Groß/klein.</summary>
    function SameAs(AOther: TAtlasRegKey): Boolean;
    /// <summary>Der Schlüssel samt Unterschlüsseln als Einträge des Vertrags (IAtlasRegistryAccess).</summary>
    function Nodes: TAtlasRegNodes;
    /// <summary>Schlüssel AName aus ANodes; nil, wenn ANodes leer ist (Schlüssel fehlt).</summary>
    class function FromNodes(const AName: string; const ANodes: TAtlasRegNodes): TAtlasRegKey; static;
    property Name: string read FName;
    property Values: TList<TAtlasRegValue> read FValues;
    property Keys: TObjectList<TAtlasRegKey> read FKeys;
  end;

  /// <summary>Lesen und Schreiben eines ganzen Schlüssels über IAtlasRegistryAccess.</summary>
  TAtlasRegistryKeys = class
  public
    /// <summary>Kopie des Schlüssels unter APath samt Unterschlüsseln; nil, wenn er fehlt. Der Aufrufer gibt das
    /// Ergebnis frei.</summary>
    class function Read(const AAccess: IAtlasRegistryAccess; const APath: string): TAtlasRegKey; static;
    /// <summary>Ersetzt den Schlüssel unter APath vollständig durch AKey; nil löscht ihn.</summary>
    class procedure Replace(const AAccess: IAtlasRegistryAccess; const APath: string; AKey: TAtlasRegKey); static;
  end;

  /// <summary>Registry im Arbeitsspeicher: Pfad → Schlüssel.</summary>
  TAtlasMemoryRegistry = class(TInterfacedObject, IAtlasRegistryAccess)
  private
    FKeys: TDictionary<string, TAtlasRegNodes>;
  public
    constructor Create;
    destructor Destroy; override;
    function Read(const APath: string): TAtlasRegNodes;
    procedure Replace(const APath: string; const ANodes: TAtlasRegNodes);
  end;

  TAtlasWelcomeBackup = class
  public const
    cFileName = 'welcomepage-layout-backup.json';
  public
    /// <summary>JSON mit Pfad, ob der Schlüssel existierte, und seinem Inhalt.</summary>
    class function Snapshot(const AAccess: IAtlasRegistryAccess; const APath: string): string; static;
    /// <summary>Schreibt den Stand aus ASnapshot zurück; False bei ungültigem Text.</summary>
    class function Restore(const AAccess: IAtlasRegistryAccess; const ASnapshot: string): Boolean; static;
    /// <summary>Entspricht der Schlüssel in der Registry dem Stand aus ASnapshot? False bei ungültigem Text.</summary>
    class function Matches(const AAccess: IAtlasRegistryAccess; const ASnapshot: string): Boolean; static;
    /// <summary>Pfad der Sicherung in AAtlasFolder (%LOCALAPPDATA%\Atlas).</summary>
    class function BackupFile(const AAtlasFolder: string): string; static;
    /// <summary>Registry-Pfad der Willkommensseite unter dem Basisschlüssel der IDE
    /// (z. B. Software\Embarcadero\BDS\37.0).</summary>
    class function WelcomeKey(const ABaseKey: string): string; static;
  end;

implementation

uses
  System.JSON;

/// <summary>Eigene Kopie von ANodes; Records mit dynamischen Arrays teilen sonst ihre Arrays.</summary>
function CopyNodes(const ANodes: TAtlasRegNodes): TAtlasRegNodes;
var
  mIndex: Integer;
begin
  Result := Copy(ANodes);
  for mIndex := 0 to High(Result) do
  begin
    Result[mIndex].Values := Copy(Result[mIndex].Values);
  end;
end;

/// <summary>AKey und seine Unterschlüssel an ANodes anhängen; APath ist der Pfad von AKey.</summary>
procedure AddNodes(AKey: TAtlasRegKey; const APath: string; var ANodes: TAtlasRegNodes);
var
  mNode: TAtlasRegNode;
  mChild: TAtlasRegKey;
  mPrefix: string;
begin
  mNode.Path := APath;
  mNode.Values := AKey.Values.ToArray;
  SetLength(ANodes, Length(ANodes) + 1);
  ANodes[High(ANodes)] := mNode;
  mPrefix := '';
  if APath <> '' then
  begin
    mPrefix := APath + '\';
  end;
  for mChild in AKey.Keys do
  begin
    AddNodes(mChild, mPrefix + mChild.Name, ANodes);
  end;
end;

/// <summary>Unterschlüssel APath von ARoot (Teile mit „\“), fehlende werden angelegt.</summary>
function KeyAt(ARoot: TAtlasRegKey; const APath: string): TAtlasRegKey;
var
  mPart: string;
  mChild: TAtlasRegKey;
begin
  Result := ARoot;
  if APath = '' then
  begin
    Exit;
  end;
  for mPart in APath.Split(['\']) do
  begin
    mChild := Result.FindKey(mPart);
    if mChild = nil then
    begin
      mChild := Result.AddKey(mPart);
    end;
    Result := mChild;
  end;
end;

const
  cKindNames: array[TAtlasRegKind] of string = ('text', 'expand', 'multi', 'dword', 'qword', 'binary');

function KindOf(const AName: string; out AKind: TAtlasRegKind): Boolean;
var
  mKind: TAtlasRegKind;
begin
  for mKind := Low(TAtlasRegKind) to High(TAtlasRegKind) do
  begin
    if SameText(cKindNames[mKind], AName) then
    begin
      AKind := mKind;
      Exit(True);
    end;
  end;
  AKind := TAtlasRegKind.Text;
  Result := False;
end;

{ TAtlasRegKey }

constructor TAtlasRegKey.Create(const AName: string);
begin
  inherited Create;
  FName := AName;
  FValues := TList<TAtlasRegValue>.Create;
  FKeys := TObjectList<TAtlasRegKey>.Create(True);
end;

destructor TAtlasRegKey.Destroy;
begin
  FKeys.Free;
  FValues.Free;
  inherited;
end;

function TAtlasRegKey.AddKey(const AName: string): TAtlasRegKey;
begin
  Result := FindKey(AName);
  if Result <> nil then
  begin
    Exit;
  end;
  Result := TAtlasRegKey.Create(AName);
  FKeys.Add(Result);
end;

function TAtlasRegKey.FindKey(const AName: string): TAtlasRegKey;
var
  mKey: TAtlasRegKey;
begin
  for mKey in FKeys do
  begin
    if SameText(mKey.Name, AName) then
    begin
      Exit(mKey);
    end;
  end;
  Result := nil;
end;

procedure TAtlasRegKey.SetValue(const AValue: TAtlasRegValue);
var
  mIndex: Integer;
begin
  for mIndex := 0 to FValues.Count - 1 do
  begin
    if SameText(FValues[mIndex].Name, AValue.Name) then
    begin
      FValues[mIndex] := AValue;
      Exit;
    end;
  end;
  FValues.Add(AValue);
end;

function TAtlasRegKey.FindValue(const AName: string; out AValue: TAtlasRegValue): Boolean;
var
  mValue: TAtlasRegValue;
begin
  for mValue in FValues do
  begin
    if SameText(mValue.Name, AName) then
    begin
      AValue := mValue;
      Exit(True);
    end;
  end;
  AValue := TAtlasRegValue.Create(AName, TAtlasRegKind.Text, '');
  Result := False;
end;

function TAtlasRegKey.Clone: TAtlasRegKey;
var
  mValue: TAtlasRegValue;
  mKey: TAtlasRegKey;
begin
  Result := TAtlasRegKey.Create(FName);
  for mValue in FValues do
  begin
    Result.FValues.Add(mValue);
  end;
  for mKey in FKeys do
  begin
    Result.FKeys.Add(mKey.Clone);
  end;
end;

function TAtlasRegKey.SameAs(AOther: TAtlasRegKey): Boolean;
var
  mValue, mOther: TAtlasRegValue;
  mKey, mOtherKey: TAtlasRegKey;
begin
  if AOther = nil then
  begin
    Exit(False);
  end;
  if (FValues.Count <> AOther.FValues.Count) or (FKeys.Count <> AOther.FKeys.Count) then
  begin
    Exit(False);
  end;
  for mValue in FValues do
  begin
    if not AOther.FindValue(mValue.Name, mOther) or not TAtlasRegValue.Same(mValue, mOther) then
    begin
      Exit(False);
    end;
  end;
  for mKey in FKeys do
  begin
    mOtherKey := AOther.FindKey(mKey.Name);
    if (mOtherKey = nil) or not mKey.SameAs(mOtherKey) then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

function KeyToJson(AKey: TAtlasRegKey): TJSONObject;
var
  mValues, mLines: TJSONArray;
  mKeys, mItem: TJSONObject;
  mValue: TAtlasRegValue;
  mLine: string;
  mKey: TAtlasRegKey;
begin
  Result := TJSONObject.Create;
  mValues := TJSONArray.Create;
  Result.AddPair('values', mValues);
  for mValue in AKey.Values do
  begin
    mItem := TJSONObject.Create;
    mItem.AddPair('name', mValue.Name);
    mItem.AddPair('kind', cKindNames[mValue.Kind]);
    if mValue.Kind = TAtlasRegKind.MultiText then
    begin
      mLines := TJSONArray.Create;
      for mLine in mValue.Lines do
      begin
        mLines.Add(mLine);
      end;
      mItem.AddPair('lines', mLines);
    end
    else
    begin
      mItem.AddPair('data', mValue.Data);
    end;
    mValues.AddElement(mItem);
  end;
  mKeys := TJSONObject.Create;
  Result.AddPair('keys', mKeys);
  for mKey in AKey.Keys do
  begin
    mKeys.AddPair(mKey.Name, KeyToJson(mKey));
  end;
end;

function KeyFromJson(const AName: string; AJson: TJSONObject; out AKey: TAtlasRegKey): Boolean; forward;

/// <summary>Inhalt eines Werts: „lines“ bei MultiText, sonst „data“; False bei falschem Typ.</summary>
function ValueDataFromJson(AItem: TJSONObject; var AValue: TAtlasRegValue): Boolean;
var
  mField: TJSONValue;
  mLines: TJSONArray;
  mIndex: Integer;
begin
  if AValue.Kind = TAtlasRegKind.MultiText then
  begin
    mField := AItem.GetValue('lines');
    Result := mField is TJSONArray;
    if Result then
    begin
      mLines := TJSONArray(mField);
      for mIndex := 0 to mLines.Count - 1 do
      begin
        AValue.Lines := AValue.Lines + [mLines.Items[mIndex].Value];
      end;
    end;
  end
  else
  begin
    mField := AItem.GetValue('data');
    Result := mField is TJSONString;
    if Result then
    begin
      AValue.Data := mField.Value;
    end;
  end;
end;

function ValueFromJson(AJson: TJSONValue; out AValue: TAtlasRegValue): Boolean;
var
  mItem: TJSONObject;
  mName, mKind: TJSONValue;
begin
  AValue := TAtlasRegValue.Create('', TAtlasRegKind.Text, '');
  Result := False;
  if not (AJson is TJSONObject) then
  begin
    Exit;
  end;
  mItem := TJSONObject(AJson);
  mName := mItem.GetValue('name');
  mKind := mItem.GetValue('kind');
  if (mName is TJSONString) and (mKind is TJSONString) and KindOf(mKind.Value, AValue.Kind) then
  begin
    AValue.Name := mName.Value;
    Result := ValueDataFromJson(mItem, AValue);
  end;
end;

/// <summary>Werte aus „values“ in AKey; fehlt das Feld, gibt es keine. False bei einem ungültigen Wert.</summary>
function ValuesFromJson(AField: TJSONValue; AKey: TAtlasRegKey): Boolean;
var
  mValues: TJSONArray;
  mIndex: Integer;
  mValue: TAtlasRegValue;
begin
  Result := True;
  if not (AField is TJSONArray) then
  begin
    Exit;
  end;
  mValues := TJSONArray(AField);
  mIndex := 0;
  while Result and (mIndex < mValues.Count) do
  begin
    Result := ValueFromJson(mValues.Items[mIndex], mValue);
    if Result then
    begin
      AKey.Values.Add(mValue);
    end;
    Inc(mIndex);
  end;
end;

/// <summary>Unterschlüssel aus „keys“ in AKey; fehlt das Feld, gibt es keine. False bei einem ungültigen.</summary>
function KeysFromJson(AField: TJSONValue; AKey: TAtlasRegKey): Boolean;
var
  mKeys: TJSONObject;
  mIndex: Integer;
  mPair: TJSONPair;
  mChild: TAtlasRegKey;
begin
  Result := True;
  if not (AField is TJSONObject) then
  begin
    Exit;
  end;
  mKeys := TJSONObject(AField);
  mIndex := 0;
  while Result and (mIndex < mKeys.Count) do
  begin
    mPair := mKeys.Pairs[mIndex];
    Result := (mPair.JsonValue is TJSONObject) and
      KeyFromJson(mPair.JsonString.Value, TJSONObject(mPair.JsonValue), mChild);
    if Result then
    begin
      AKey.Keys.Add(mChild);
    end;
    Inc(mIndex);
  end;
end;

function KeyFromJson(const AName: string; AJson: TJSONObject; out AKey: TAtlasRegKey): Boolean;
begin
  AKey := TAtlasRegKey.Create(AName);
  try
    Result := ValuesFromJson(AJson.GetValue('values'), AKey) and KeysFromJson(AJson.GetValue('keys'), AKey);
  except
    FreeAndNil(AKey);
    raise;
  end;
  if not Result then
  begin
    FreeAndNil(AKey);
  end;
end;

function TAtlasRegKey.Nodes: TAtlasRegNodes;
begin
  Result := nil;
  AddNodes(Self, '', Result);
end;

class function TAtlasRegKey.FromNodes(const AName: string; const ANodes: TAtlasRegNodes): TAtlasRegKey;
var
  mNode: TAtlasRegNode;
  mKey: TAtlasRegKey;
  mValue: TAtlasRegValue;
begin
  if Length(ANodes) = 0 then
  begin
    Exit(nil);
  end;
  Result := TAtlasRegKey.Create(AName);
  for mNode in ANodes do
  begin
    mKey := KeyAt(Result, mNode.Path);
    for mValue in mNode.Values do
    begin
      mKey.SetValue(mValue);
    end;
  end;
end;

{ TAtlasRegistryKeys }

class function TAtlasRegistryKeys.Read(const AAccess: IAtlasRegistryAccess; const APath: string): TAtlasRegKey;
begin
  Result := TAtlasRegKey.FromNodes(ExtractFileName(APath), AAccess.Read(APath));
end;

class procedure TAtlasRegistryKeys.Replace(const AAccess: IAtlasRegistryAccess; const APath: string;
  AKey: TAtlasRegKey);
var
  mNodes: TAtlasRegNodes;
begin
  mNodes := nil;
  if AKey <> nil then
  begin
    mNodes := AKey.Nodes;
  end;
  AAccess.Replace(APath, mNodes);
end;

{ TAtlasMemoryRegistry }

constructor TAtlasMemoryRegistry.Create;
begin
  inherited Create;
  FKeys := TDictionary<string, TAtlasRegNodes>.Create;
end;

destructor TAtlasMemoryRegistry.Destroy;
begin
  FKeys.Free;
  inherited;
end;

function TAtlasMemoryRegistry.Read(const APath: string): TAtlasRegNodes;
var
  mNodes: TAtlasRegNodes;
begin
  Result := nil;
  if FKeys.TryGetValue(LowerCase(APath), mNodes) then
  begin
    Result := CopyNodes(mNodes);
  end;
end;

procedure TAtlasMemoryRegistry.Replace(const APath: string; const ANodes: TAtlasRegNodes);
begin
  FKeys.Remove(LowerCase(APath));
  if Length(ANodes) > 0 then
  begin
    FKeys.Add(LowerCase(APath), CopyNodes(ANodes));
  end;
end;

{ TAtlasWelcomeBackup }

class function TAtlasWelcomeBackup.Snapshot(const AAccess: IAtlasRegistryAccess; const APath: string): string;
var
  mRoot: TJSONObject;
  mKey: TAtlasRegKey;
begin
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('path', APath);
    mKey := TAtlasRegistryKeys.Read(AAccess, APath);
    try
      mRoot.AddPair('existed', TJSONBool.Create(mKey <> nil));
      if mKey <> nil then
      begin
        mRoot.AddPair('key', KeyToJson(mKey));
      end;
    finally
      mKey.Free;
    end;
    Result := mRoot.ToJSON;
  finally
    mRoot.Free;
  end;
end;

class function TAtlasWelcomeBackup.Restore(const AAccess: IAtlasRegistryAccess; const ASnapshot: string): Boolean;
var
  mValue, mField: TJSONValue;
  mRoot: TJSONObject;
  mPath: string;
  mKey: TAtlasRegKey;
begin
  Result := False;
  mValue := TJSONObject.ParseJSONValue(ASnapshot);
  try
    if not (mValue is TJSONObject) then
    begin
      Exit;
    end;
    mRoot := TJSONObject(mValue);
    mField := mRoot.GetValue('path');
    if not (mField is TJSONString) or (mField.Value = '') then
    begin
      Exit;
    end;
    mPath := mField.Value;
    mField := mRoot.GetValue('key');
    if mField is TJSONObject then
    begin
      if not KeyFromJson('', TJSONObject(mField), mKey) then
      begin
        Exit;
      end;
      try
        TAtlasRegistryKeys.Replace(AAccess, mPath, mKey);
      finally
        mKey.Free;
      end;
    end
    else
    begin
      // Vorher gab es den Schlüssel nicht: wieder entfernen.
      TAtlasRegistryKeys.Replace(AAccess, mPath, nil);
    end;
    Result := True;
  finally
    mValue.Free;
  end;
end;

class function TAtlasWelcomeBackup.Matches(const AAccess: IAtlasRegistryAccess; const ASnapshot: string): Boolean;
var
  mValue, mField: TJSONValue;
  mRoot: TJSONObject;
  mCurrent, mKey: TAtlasRegKey;
begin
  Result := False;
  mValue := TJSONObject.ParseJSONValue(ASnapshot);
  try
    if not (mValue is TJSONObject) then
    begin
      Exit;
    end;
    mRoot := TJSONObject(mValue);
    mField := mRoot.GetValue('path');
    if not (mField is TJSONString) or (mField.Value = '') then
    begin
      Exit;
    end;
    mCurrent := TAtlasRegistryKeys.Read(AAccess, mField.Value);
    try
      mField := mRoot.GetValue('key');
      if mField is TJSONObject then
      begin
        if not KeyFromJson('', TJSONObject(mField), mKey) then
        begin
          Exit;
        end;
        try
          Result := mKey.SameAs(mCurrent);
        finally
          mKey.Free;
        end;
      end
      else
      begin
        Result := mCurrent = nil;
      end;
    finally
      mCurrent.Free;
    end;
  finally
    mValue.Free;
  end;
end;

class function TAtlasWelcomeBackup.BackupFile(const AAtlasFolder: string): string;
begin
  Result := IncludeTrailingPathDelimiter(AAtlasFolder) + cFileName;
end;

class function TAtlasWelcomeBackup.WelcomeKey(const ABaseKey: string): string;
var
  mBase: string;
begin
  mBase := ABaseKey;
  while (mBase <> '') and (mBase[1] = '\') do
  begin
    Delete(mBase, 1, 1);
  end;
  while (mBase <> '') and (mBase[Length(mBase)] = '\') do
  begin
    Delete(mBase, Length(mBase), 1);
  end;
  Result := mBase + '\WelcomePage';
end;

end.
