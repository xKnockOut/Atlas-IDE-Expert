unit Atlas.Core.Welcome.Backup;

// Sicherung des Willkommensseiten-Layouts der IDE (#753), ohne Windows:
// Der Registry-Schlüssel der IDE (HKCU\Software\Embarcadero\BDS\<Version>\
// WelcomePage) samt Unterschlüsseln und allen Werten mit Typ als JSON. Frühere
// Fassungen sicherten ihn vor „Atlas-Layout anwenden“; seit #1114 schreibt
// TAtlasWelcomeRetire eine solche Sicherung beim Start exakt zurück (auch:
// Schlüssel fehlte vorher → wieder löschen), und die Marke für den
// gewünschten Stand nutzt dasselbe Format. Den Zugriff auf die Registry liefert die IDE-Schicht über
// IAtlasRegistryAccess; TAtlasMemoryRegistry dient Tests und Vergleichen.

interface

uses
  System.SysUtils,
  System.Generics.Collections;

type
{$SCOPEDENUMS ON}
  /// <summary>REG_SZ, REG_EXPAND_SZ, REG_MULTI_SZ, REG_DWORD, REG_QWORD, REG_BINARY.</summary>
  TAtlasRegKind = (Text, ExpandText, MultiText, Number, Number64, Binary);
{$SCOPEDENUMS OFF}

  TAtlasRegValue = record
    Name: string;
    Kind: TAtlasRegKind;
    /// <summary>Text; Zahlen dezimal; Binärdaten als Hex ohne Trenner.</summary>
    Data: string;
    /// <summary>Nur MultiText.</summary>
    Lines: TArray<string>;
    class function Create(const AName: string; AKind: TAtlasRegKind; const AData: string): TAtlasRegValue; static;
    class function Same(const ALeft, ARight: TAtlasRegValue): Boolean; static;
  end;

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
    /// <summary>Gleiche Werte (Name, Typ, Inhalt) und Unterschlüssel, Reihenfolge egal, Namen ohne Groß/klein.</summary>
    function SameAs(AOther: TAtlasRegKey): Boolean;
    function ToJsonText: string;
    /// <summary>nil bei ungültigem Text.</summary>
    class function FromJsonText(const AText: string): TAtlasRegKey; static;
    property Name: string read FName;
    property Values: TList<TAtlasRegValue> read FValues;
    property Keys: TObjectList<TAtlasRegKey> read FKeys;
  end;

  IAtlasRegistryAccess = interface
    ['{8E4C6B21-0F3D-4A79-B5E2-6C19D7A043F8}']
    /// <summary>Kopie des Schlüssels unter APath (relativ zu HKCU) samt Unterschlüsseln; nil, wenn er fehlt.
    /// Der Aufrufer gibt das Ergebnis frei.</summary>
    function Read(const APath: string): TAtlasRegKey;
    /// <summary>Ersetzt den Schlüssel unter APath vollständig durch AKey; nil löscht ihn.</summary>
    procedure Replace(const APath: string; AKey: TAtlasRegKey);
  end;

  /// <summary>Registry im Arbeitsspeicher: Pfad → Schlüssel.</summary>
  TAtlasMemoryRegistry = class(TInterfacedObject, IAtlasRegistryAccess)
  private
    FKeys: TObjectDictionary<string, TAtlasRegKey>;
  public
    constructor Create;
    destructor Destroy; override;
    function Read(const APath: string): TAtlasRegKey;
    procedure Replace(const APath: string; AKey: TAtlasRegKey);
  end;

  TAtlasWelcomeBackup = class
  public const
    FileName = 'welcomepage-layout-backup.json';
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

const
  KindNames: array[TAtlasRegKind] of string = ('text', 'expand', 'multi', 'dword', 'qword', 'binary');

function KindOf(const AName: string; out AKind: TAtlasRegKind): Boolean;
var
  Kind: TAtlasRegKind;
begin
  for Kind := Low(TAtlasRegKind) to High(TAtlasRegKind) do
    if SameText(KindNames[Kind], AName) then
    begin
      AKind := Kind;
      Exit(True);
    end;
  AKind := TAtlasRegKind.Text;
  Result := False;
end;

{ TAtlasRegValue }

class function TAtlasRegValue.Create(const AName: string; AKind: TAtlasRegKind; const AData: string): TAtlasRegValue;
begin
  Result.Name := AName;
  Result.Kind := AKind;
  Result.Data := AData;
  Result.Lines := nil;
end;

class function TAtlasRegValue.Same(const ALeft, ARight: TAtlasRegValue): Boolean;
var
  Index: Integer;
begin
  Result := SameText(ALeft.Name, ARight.Name) and (ALeft.Kind = ARight.Kind) and (ALeft.Data = ARight.Data) and
    (Length(ALeft.Lines) = Length(ARight.Lines));
  if not Result then
    Exit;
  for Index := 0 to High(ALeft.Lines) do
    if ALeft.Lines[Index] <> ARight.Lines[Index] then
      Exit(False);
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
    Exit;
  Result := TAtlasRegKey.Create(AName);
  FKeys.Add(Result);
end;

function TAtlasRegKey.FindKey(const AName: string): TAtlasRegKey;
var
  Key: TAtlasRegKey;
begin
  for Key in FKeys do
    if SameText(Key.Name, AName) then
      Exit(Key);
  Result := nil;
end;

procedure TAtlasRegKey.SetValue(const AValue: TAtlasRegValue);
var
  Index: Integer;
begin
  for Index := 0 to FValues.Count - 1 do
    if SameText(FValues[Index].Name, AValue.Name) then
    begin
      FValues[Index] := AValue;
      Exit;
    end;
  FValues.Add(AValue);
end;

function TAtlasRegKey.FindValue(const AName: string; out AValue: TAtlasRegValue): Boolean;
var
  Value: TAtlasRegValue;
begin
  for Value in FValues do
    if SameText(Value.Name, AName) then
    begin
      AValue := Value;
      Exit(True);
    end;
  AValue := TAtlasRegValue.Create(AName, TAtlasRegKind.Text, '');
  Result := False;
end;

function TAtlasRegKey.Clone: TAtlasRegKey;
var
  Value: TAtlasRegValue;
  Key: TAtlasRegKey;
begin
  Result := TAtlasRegKey.Create(FName);
  for Value in FValues do
    Result.FValues.Add(Value);
  for Key in FKeys do
    Result.FKeys.Add(Key.Clone);
end;

function TAtlasRegKey.SameAs(AOther: TAtlasRegKey): Boolean;
var
  Value, Other: TAtlasRegValue;
  Key, OtherKey: TAtlasRegKey;
begin
  if AOther = nil then
    Exit(False);
  if (FValues.Count <> AOther.FValues.Count) or (FKeys.Count <> AOther.FKeys.Count) then
    Exit(False);
  for Value in FValues do
    if not AOther.FindValue(Value.Name, Other) or not TAtlasRegValue.Same(Value, Other) then
      Exit(False);
  for Key in FKeys do
  begin
    OtherKey := AOther.FindKey(Key.Name);
    if (OtherKey = nil) or not Key.SameAs(OtherKey) then
      Exit(False);
  end;
  Result := True;
end;

function KeyToJson(AKey: TAtlasRegKey): TJSONObject;
var
  Values, Lines: TJSONArray;
  Keys, Item: TJSONObject;
  Value: TAtlasRegValue;
  Line: string;
  Key: TAtlasRegKey;
begin
  Result := TJSONObject.Create;
  Values := TJSONArray.Create;
  Result.AddPair('values', Values);
  for Value in AKey.Values do
  begin
    Item := TJSONObject.Create;
    Item.AddPair('name', Value.Name);
    Item.AddPair('kind', KindNames[Value.Kind]);
    if Value.Kind = TAtlasRegKind.MultiText then
    begin
      Lines := TJSONArray.Create;
      for Line in Value.Lines do
        Lines.Add(Line);
      Item.AddPair('lines', Lines);
    end
    else
      Item.AddPair('data', Value.Data);
    Values.AddElement(Item);
  end;
  Keys := TJSONObject.Create;
  Result.AddPair('keys', Keys);
  for Key in AKey.Keys do
    Keys.AddPair(Key.Name, KeyToJson(Key));
end;

function KeyFromJson(const AName: string; AJson: TJSONObject; out AKey: TAtlasRegKey): Boolean;
var
  Field, LinesField: TJSONValue;
  Values, Lines: TJSONArray;
  Keys, Item: TJSONObject;
  Index, LineIndex: Integer;
  Value: TAtlasRegValue;
  Kind: TAtlasRegKind;
  Child: TAtlasRegKey;
begin
  AKey := TAtlasRegKey.Create(AName);
  Result := False;
  try
    Field := AJson.GetValue('values');
    if Field is TJSONArray then
    begin
      Values := TJSONArray(Field);
      for Index := 0 to Values.Count - 1 do
      begin
        if not (Values.Items[Index] is TJSONObject) then
          Exit;
        Item := TJSONObject(Values.Items[Index]);
        Field := Item.GetValue('name');
        if not (Field is TJSONString) then
          Exit;
        Value := TAtlasRegValue.Create(Field.Value, TAtlasRegKind.Text, '');
        Field := Item.GetValue('kind');
        if not (Field is TJSONString) or not KindOf(Field.Value, Kind) then
          Exit;
        Value.Kind := Kind;
        if Kind = TAtlasRegKind.MultiText then
        begin
          LinesField := Item.GetValue('lines');
          if not (LinesField is TJSONArray) then
            Exit;
          Lines := TJSONArray(LinesField);
          for LineIndex := 0 to Lines.Count - 1 do
            Value.Lines := Value.Lines + [Lines.Items[LineIndex].Value];
        end
        else
        begin
          Field := Item.GetValue('data');
          if not (Field is TJSONString) then
            Exit;
          Value.Data := Field.Value;
        end;
        AKey.Values.Add(Value);
      end;
    end;
    Field := AJson.GetValue('keys');
    if Field is TJSONObject then
    begin
      Keys := TJSONObject(Field);
      for Index := 0 to Keys.Count - 1 do
      begin
        if not (Keys.Pairs[Index].JsonValue is TJSONObject) then
          Exit;
        if not KeyFromJson(Keys.Pairs[Index].JsonString.Value, TJSONObject(Keys.Pairs[Index].JsonValue), Child) then
          Exit;
        AKey.Keys.Add(Child);
      end;
    end;
    Result := True;
  finally
    if not Result then
      FreeAndNil(AKey);
  end;
end;

function TAtlasRegKey.ToJsonText: string;
var
  Json: TJSONObject;
begin
  Json := KeyToJson(Self);
  try
    Result := Json.ToJSON;
  finally
    Json.Free;
  end;
end;

class function TAtlasRegKey.FromJsonText(const AText: string): TAtlasRegKey;
var
  Value: TJSONValue;
begin
  Result := nil;
  Value := TJSONObject.ParseJSONValue(AText);
  try
    if Value is TJSONObject then
      KeyFromJson('', TJSONObject(Value), Result);
  finally
    Value.Free;
  end;
end;

{ TAtlasMemoryRegistry }

constructor TAtlasMemoryRegistry.Create;
begin
  inherited Create;
  FKeys := TObjectDictionary<string, TAtlasRegKey>.Create([doOwnsValues]);
end;

destructor TAtlasMemoryRegistry.Destroy;
begin
  FKeys.Free;
  inherited;
end;

function TAtlasMemoryRegistry.Read(const APath: string): TAtlasRegKey;
var
  Key: TAtlasRegKey;
begin
  Result := nil;
  if FKeys.TryGetValue(LowerCase(APath), Key) then
    Result := Key.Clone;
end;

procedure TAtlasMemoryRegistry.Replace(const APath: string; AKey: TAtlasRegKey);
begin
  FKeys.Remove(LowerCase(APath));
  if AKey <> nil then
    FKeys.Add(LowerCase(APath), AKey.Clone);
end;

{ TAtlasWelcomeBackup }

class function TAtlasWelcomeBackup.Snapshot(const AAccess: IAtlasRegistryAccess; const APath: string): string;
var
  Root: TJSONObject;
  Key: TAtlasRegKey;
begin
  Root := TJSONObject.Create;
  try
    Root.AddPair('path', APath);
    Key := AAccess.Read(APath);
    try
      Root.AddPair('existed', TJSONBool.Create(Key <> nil));
      if Key <> nil then
        Root.AddPair('key', KeyToJson(Key));
    finally
      Key.Free;
    end;
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

class function TAtlasWelcomeBackup.Restore(const AAccess: IAtlasRegistryAccess; const ASnapshot: string): Boolean;
var
  Value, Field: TJSONValue;
  Root: TJSONObject;
  Path: string;
  Key: TAtlasRegKey;
begin
  Result := False;
  Value := TJSONObject.ParseJSONValue(ASnapshot);
  try
    if not (Value is TJSONObject) then
      Exit;
    Root := TJSONObject(Value);
    Field := Root.GetValue('path');
    if not (Field is TJSONString) or (Field.Value = '') then
      Exit;
    Path := Field.Value;
    Field := Root.GetValue('key');
    if Field is TJSONObject then
    begin
      if not KeyFromJson('', TJSONObject(Field), Key) then
        Exit;
      try
        AAccess.Replace(Path, Key);
      finally
        Key.Free;
      end;
    end
    else
      // Vorher gab es den Schlüssel nicht: wieder entfernen.
      AAccess.Replace(Path, nil);
    Result := True;
  finally
    Value.Free;
  end;
end;

class function TAtlasWelcomeBackup.Matches(const AAccess: IAtlasRegistryAccess; const ASnapshot: string): Boolean;
var
  Value, Field: TJSONValue;
  Root: TJSONObject;
  Current, Key: TAtlasRegKey;
begin
  Result := False;
  Value := TJSONObject.ParseJSONValue(ASnapshot);
  try
    if not (Value is TJSONObject) then
      Exit;
    Root := TJSONObject(Value);
    Field := Root.GetValue('path');
    if not (Field is TJSONString) or (Field.Value = '') then
      Exit;
    Current := AAccess.Read(Field.Value);
    try
      Field := Root.GetValue('key');
      if Field is TJSONObject then
      begin
        if not KeyFromJson('', TJSONObject(Field), Key) then
          Exit;
        try
          Result := Key.SameAs(Current);
        finally
          Key.Free;
        end;
      end
      else
        Result := Current = nil;
    finally
      Current.Free;
    end;
  finally
    Value.Free;
  end;
end;

class function TAtlasWelcomeBackup.BackupFile(const AAtlasFolder: string): string;
begin
  Result := IncludeTrailingPathDelimiter(AAtlasFolder) + FileName;
end;

class function TAtlasWelcomeBackup.WelcomeKey(const ABaseKey: string): string;
var
  Base: string;
begin
  Base := ABaseKey;
  while (Base <> '') and (Base[1] = '\') do
    Delete(Base, 1, 1);
  while (Base <> '') and (Base[Length(Base)] = '\') do
    Delete(Base, Length(Base), 1);
  Result := Base + '\WelcomePage';
end;

end.
