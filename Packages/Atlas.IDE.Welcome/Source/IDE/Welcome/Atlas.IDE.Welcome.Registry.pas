unit Atlas.IDE.Welcome.Registry;

// Zugriff auf HKCU für die Sicherung des Willkommensseiten-Layouts (#753):
// liest einen Schlüssel samt Unterschlüsseln mit allen Werten und Typen in
// einen TAtlasRegKey und schreibt ihn exakt zurück (vorher wird der Schlüssel
// gelöscht, damit keine Reste bleiben). Basisschlüssel der IDE aus
// IOTAServices.GetBaseRegistryKey (z. B. Software\Embarcadero\BDS\37.0).

interface

uses
  System.SysUtils,
  Atlas.Core.Welcome.Backup;

type
  TAtlasIdeRegistryAccess = class(TInterfacedObject, IAtlasRegistryAccess)
  public
    function Read(const APath: string): TAtlasRegKey;
    procedure Replace(const APath: string; AKey: TAtlasRegKey);
    /// <summary>Basisschlüssel der laufenden IDE ohne führenden Backslash.</summary>
    class function IdeBaseKey: string; static;
  end;

implementation

uses
  Winapi.Windows,
  System.Classes,
  System.Win.Registry,
  ToolsAPI;

const
  // REG_QWORD; nicht in jeder Fassung von Winapi.Windows.
  RegQWord = 11;

function HexOf(const ABytes: TBytes): string;
var
  Index: Integer;
begin
  Result := '';
  for Index := 0 to High(ABytes) do
    Result := Result + IntToHex(ABytes[Index], 2);
end;

function BytesOf(const AHex: string): TBytes;
var
  Index: Integer;
begin
  SetLength(Result, Length(AHex) div 2);
  for Index := 0 to High(Result) do
    Result[Index] := StrToIntDef('$' + Copy(AHex, Index * 2 + 1, 2), 0);
end;

/// <summary>Rohdaten eines Werts (für REG_MULTI_SZ und REG_QWORD, die TRegistry nicht direkt liest).</summary>
function RawValue(AKey: HKEY; const AName: string; out AType: DWORD): TBytes;
var
  Size: DWORD;
begin
  Result := nil;
  Size := 0;
  if RegQueryValueEx(AKey, PChar(AName), nil, @AType, nil, @Size) <> ERROR_SUCCESS then
    Exit;
  SetLength(Result, Size);
  if (Size > 0) and (RegQueryValueEx(AKey, PChar(AName), nil, @AType, PByte(Result), @Size) <> ERROR_SUCCESS) then
    Result := nil;
end;

function MultiLines(const ABytes: TBytes): TArray<string>;
var
  Text: string;
  Start, Index: Integer;
begin
  Result := nil;
  if Length(ABytes) < SizeOf(Char) then
    Exit;
  SetString(Text, PChar(@ABytes[0]), Length(ABytes) div SizeOf(Char));
  // Abschließende Nullen: eine je Eintrag plus eine am Ende.
  while (Text <> '') and (Text[Length(Text)] = #0) do
    Delete(Text, Length(Text), 1);
  if Text = '' then
    Exit;
  // Von Hand teilen: TStrings.DelimitedText bricht an #0 ab.
  Start := 1;
  for Index := 1 to Length(Text) do
    if Text[Index] = #0 then
    begin
      Result := Result + [Copy(Text, Start, Index - Start)];
      Start := Index + 1;
    end;
  Result := Result + [Copy(Text, Start, MaxInt)];
end;

procedure ReadKey(ARegistry: TRegistry; const APath: string; AKey: TAtlasRegKey);
var
  Names: TStringList;
  Name: string;
  Kind: DWORD;
  Raw: TBytes;
  Value: TAtlasRegValue;
  Sub: TArray<string>;
  Index: Integer;
  QWord: UInt64;
begin
  if not ARegistry.OpenKeyReadOnly('\' + APath) then
    Exit;
  Names := TStringList.Create;
  try
    ARegistry.GetValueNames(Names);
    for Name in Names do
    begin
      Raw := RawValue(ARegistry.CurrentKey, Name, Kind);
      case Kind of
        REG_SZ:
          Value := TAtlasRegValue.Create(Name, TAtlasRegKind.Text, ARegistry.ReadString(Name));
        REG_EXPAND_SZ:
          Value := TAtlasRegValue.Create(Name, TAtlasRegKind.ExpandText, ARegistry.ReadString(Name));
        REG_DWORD:
          Value := TAtlasRegValue.Create(Name, TAtlasRegKind.Number, IntToStr(Cardinal(ARegistry.ReadInteger(Name))));
        RegQWord:
          begin
            QWord := 0;
            if Length(Raw) >= SizeOf(QWord) then
              Move(Raw[0], QWord, SizeOf(QWord));
            Value := TAtlasRegValue.Create(Name, TAtlasRegKind.Number64, UIntToStr(QWord));
          end;
        REG_MULTI_SZ:
          begin
            Value := TAtlasRegValue.Create(Name, TAtlasRegKind.MultiText, '');
            Value.Lines := MultiLines(Raw);
          end;
      else
        Value := TAtlasRegValue.Create(Name, TAtlasRegKind.Binary, HexOf(Raw));
      end;
      AKey.Values.Add(Value);
    end;
    Names.Clear;
    ARegistry.GetKeyNames(Names);
    Sub := Names.ToStringArray;
  finally
    Names.Free;
    ARegistry.CloseKey;
  end;
  for Index := 0 to High(Sub) do
    ReadKey(ARegistry, APath + '\' + Sub[Index], AKey.AddKey(Sub[Index]));
end;

function TAtlasIdeRegistryAccess.Read(const APath: string): TAtlasRegKey;
var
  Registry: TRegistry;
begin
  Result := nil;
  Registry := TRegistry.Create(KEY_READ);
  try
    Registry.RootKey := HKEY_CURRENT_USER;
    if not Registry.KeyExists('\' + APath) then
      Exit;
    Result := TAtlasRegKey.Create(ExtractFileName(APath));
    ReadKey(Registry, APath, Result);
  finally
    Registry.Free;
  end;
end;

procedure WriteKey(ARegistry: TRegistry; const APath: string; AKey: TAtlasRegKey);
var
  Value: TAtlasRegValue;
  Bytes: TBytes;
  Text: string;
  QWord: UInt64;
  Line: string;
  Child: TAtlasRegKey;
begin
  if not ARegistry.OpenKey('\' + APath, True) then
    raise ERegistryException.CreateFmt('Schlüssel %s nicht beschreibbar', [APath]);
  try
    for Value in AKey.Values do
      case Value.Kind of
        TAtlasRegKind.Text:
          ARegistry.WriteString(Value.Name, Value.Data);
        TAtlasRegKind.ExpandText:
          ARegistry.WriteExpandString(Value.Name, Value.Data);
        TAtlasRegKind.Number:
          ARegistry.WriteInteger(Value.Name, Integer(Cardinal(StrToUInt64Def(Value.Data, 0))));
        TAtlasRegKind.Number64:
          begin
            QWord := StrToUInt64Def(Value.Data, 0);
            RegSetValueEx(ARegistry.CurrentKey, PChar(Value.Name), 0, RegQWord, @QWord, SizeOf(QWord));
          end;
        TAtlasRegKind.MultiText:
          begin
            Text := '';
            for Line in Value.Lines do
              Text := Text + Line + #0;
            Text := Text + #0;
            RegSetValueEx(ARegistry.CurrentKey, PChar(Value.Name), 0, REG_MULTI_SZ, PChar(Text),
              Length(Text) * SizeOf(Char));
          end;
      else
        begin
          Bytes := BytesOf(Value.Data);
          if Length(Bytes) > 0 then
            ARegistry.WriteBinaryData(Value.Name, Bytes[0], Length(Bytes))
          else
            RegSetValueEx(ARegistry.CurrentKey, PChar(Value.Name), 0, REG_BINARY, nil, 0);
        end;
      end;
  finally
    ARegistry.CloseKey;
  end;
  for Child in AKey.Keys do
    WriteKey(ARegistry, APath + '\' + Child.Name, Child);
end;

procedure TAtlasIdeRegistryAccess.Replace(const APath: string; AKey: TAtlasRegKey);
var
  Registry: TRegistry;
begin
  Registry := TRegistry.Create(KEY_READ or KEY_WRITE);
  try
    Registry.RootKey := HKEY_CURRENT_USER;
    // DeleteKey löscht unter Windows auch Unterschlüssel (RegDeleteTree).
    if Registry.KeyExists('\' + APath) then
      Registry.DeleteKey('\' + APath);
    if AKey <> nil then
      WriteKey(Registry, APath, AKey);
  finally
    Registry.Free;
  end;
end;

class function TAtlasIdeRegistryAccess.IdeBaseKey: string;
var
  Services: IOTAServices;
begin
  Result := '';
  if Supports(BorlandIDEServices, IOTAServices, Services) then
    Result := Services.GetBaseRegistryKey;
  while (Result <> '') and (Result[1] = '\') do
    Delete(Result, 1, 1);
end;

end.
