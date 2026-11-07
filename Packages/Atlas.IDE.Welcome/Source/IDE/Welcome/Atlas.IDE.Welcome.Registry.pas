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
  cRegQWord = 11;

function HexOf(const ABytes: TBytes): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := 0 to High(ABytes) do
  begin
    Result := Result + IntToHex(ABytes[mIndex], 2);
  end;
end;

function BytesOf(const AHex: string): TBytes;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(AHex) div 2);
  for mIndex := 0 to High(Result) do
  begin
    Result[mIndex] := StrToIntDef('$' + Copy(AHex, mIndex * 2 + 1, 2), 0);
  end;
end;

/// <summary>Rohdaten eines Werts (für REG_MULTI_SZ und REG_QWORD, die TRegistry nicht direkt liest).</summary>
function RawValue(AKey: HKEY; const AName: string; out AType: DWORD): TBytes;
var
  mSize: DWORD;
begin
  Result := nil;
  mSize := 0;
  if RegQueryValueEx(AKey, PChar(AName), nil, @AType, nil, @mSize) <> ERROR_SUCCESS then
  begin
    Exit;
  end;
  SetLength(Result, mSize);
  if (mSize > 0) and (RegQueryValueEx(AKey, PChar(AName), nil, @AType, PByte(Result), @mSize) <> ERROR_SUCCESS) then
  begin
    Result := nil;
  end;
end;

function MultiLines(const ABytes: TBytes): TArray<string>;
var
  mText: string;
  mStart, mIndex: Integer;
begin
  Result := nil;
  if Length(ABytes) < SizeOf(Char) then
  begin
    Exit;
  end;
  SetString(mText, PChar(@ABytes[0]), Length(ABytes) div SizeOf(Char));
  // Abschließende Nullen: eine je Eintrag plus eine am Ende.
  while (mText <> '') and (mText[Length(mText)] = #0) do
  begin
    Delete(mText, Length(mText), 1);
  end;
  if mText = '' then
  begin
    Exit;
  end;
  // Von Hand teilen: TStrings.DelimitedText bricht an #0 ab.
  mStart := 1;
  for mIndex := 1 to Length(mText) do
  begin
    if mText[mIndex] = #0 then
    begin
      Result := Result + [Copy(mText, mStart, mIndex - mStart)];
      mStart := mIndex + 1;
    end;
  end;
  Result := Result + [Copy(mText, mStart, MaxInt)];
end;

procedure ReadKey(ARegistry: TRegistry; const APath: string; AKey: TAtlasRegKey);
var
  mNames: TStringList;
  mName: string;
  mKind: DWORD;
  mRaw: TBytes;
  mValue: TAtlasRegValue;
  mSub: TArray<string>;
  mIndex: Integer;
  mQWord: UInt64;
begin
  if not ARegistry.OpenKeyReadOnly('\' + APath) then
  begin
    Exit;
  end;
  mNames := TStringList.Create;
  try
    ARegistry.GetValueNames(mNames);
    for mName in mNames do
    begin
      mRaw := RawValue(ARegistry.CurrentKey, mName, mKind);
      case mKind of
        REG_SZ:
          mValue := TAtlasRegValue.Create(mName, TAtlasRegKind.Text, ARegistry.ReadString(mName));
        REG_EXPAND_SZ:
          mValue := TAtlasRegValue.Create(mName, TAtlasRegKind.ExpandText, ARegistry.ReadString(mName));
        REG_DWORD:
          mValue := TAtlasRegValue.Create(mName, TAtlasRegKind.Number,
            IntToStr(Cardinal(ARegistry.ReadInteger(mName))));
        cRegQWord:
          begin
            mQWord := 0;
            if Length(mRaw) >= SizeOf(mQWord) then
            begin
              Move(mRaw[0], mQWord, SizeOf(mQWord));
            end;
            mValue := TAtlasRegValue.Create(mName, TAtlasRegKind.Number64, UIntToStr(mQWord));
          end;
        REG_MULTI_SZ:
          begin
            mValue := TAtlasRegValue.Create(mName, TAtlasRegKind.MultiText, '');
            mValue.Lines := MultiLines(mRaw);
          end;
      else
        mValue := TAtlasRegValue.Create(mName, TAtlasRegKind.Binary, HexOf(mRaw));
      end;
      AKey.Values.Add(mValue);
    end;
    mNames.Clear;
    ARegistry.GetKeyNames(mNames);
    mSub := mNames.ToStringArray;
  finally
    mNames.Free;
    ARegistry.CloseKey;
  end;
  for mIndex := 0 to High(mSub) do
  begin
    ReadKey(ARegistry, APath + '\' + mSub[mIndex], AKey.AddKey(mSub[mIndex]));
  end;
end;

function TAtlasIdeRegistryAccess.Read(const APath: string): TAtlasRegKey;
var
  mRegistry: TRegistry;
begin
  Result := nil;
  mRegistry := TRegistry.Create(KEY_READ);
  try
    mRegistry.RootKey := HKEY_CURRENT_USER;
    if not mRegistry.KeyExists('\' + APath) then
    begin
      Exit;
    end;
    Result := TAtlasRegKey.Create(ExtractFileName(APath));
    ReadKey(mRegistry, APath, Result);
  finally
    mRegistry.Free;
  end;
end;

procedure WriteKey(ARegistry: TRegistry; const APath: string; AKey: TAtlasRegKey);
var
  mValue: TAtlasRegValue;
  mBytes: TBytes;
  mText: string;
  mQWord: UInt64;
  mLine: string;
  mChild: TAtlasRegKey;
begin
  if not ARegistry.OpenKey('\' + APath, True) then
  begin
    raise ERegistryException.CreateFmt('Schlüssel %s nicht beschreibbar', [APath]);
  end;
  try
    for mValue in AKey.Values do
      case mValue.Kind of
        TAtlasRegKind.Text:
          ARegistry.WriteString(mValue.Name, mValue.Data);
        TAtlasRegKind.ExpandText:
          ARegistry.WriteExpandString(mValue.Name, mValue.Data);
        TAtlasRegKind.Number:
          ARegistry.WriteInteger(mValue.Name, Integer(Cardinal(StrToUInt64Def(mValue.Data, 0))));
        TAtlasRegKind.Number64:
          begin
            mQWord := StrToUInt64Def(mValue.Data, 0);
            RegSetValueEx(ARegistry.CurrentKey, PChar(mValue.Name), 0, cRegQWord, @mQWord, SizeOf(mQWord));
          end;
        TAtlasRegKind.MultiText:
          begin
            mText := '';
            for mLine in mValue.Lines do
            begin
              mText := mText + mLine + #0;
            end;
            mText := mText + #0;
            RegSetValueEx(ARegistry.CurrentKey, PChar(mValue.Name), 0, REG_MULTI_SZ, PChar(mText),
              Length(mText) * SizeOf(Char));
          end;
      else
        begin
          mBytes := BytesOf(mValue.Data);
          if Length(mBytes) > 0 then
          begin
            ARegistry.WriteBinaryData(mValue.Name, mBytes[0], Length(mBytes));
          end
          else
          begin
            RegSetValueEx(ARegistry.CurrentKey, PChar(mValue.Name), 0, REG_BINARY, nil, 0);
          end;
        end;
      end;
  finally
    ARegistry.CloseKey;
  end;
  for mChild in AKey.Keys do
  begin
    WriteKey(ARegistry, APath + '\' + mChild.Name, mChild);
  end;
end;

procedure TAtlasIdeRegistryAccess.Replace(const APath: string; AKey: TAtlasRegKey);
var
  mRegistry: TRegistry;
begin
  mRegistry := TRegistry.Create(KEY_READ or KEY_WRITE);
  try
    mRegistry.RootKey := HKEY_CURRENT_USER;
    // DeleteKey löscht unter Windows auch Unterschlüssel (RegDeleteTree).
    if mRegistry.KeyExists('\' + APath) then
    begin
      mRegistry.DeleteKey('\' + APath);
    end;
    if AKey <> nil then
    begin
      WriteKey(mRegistry, APath, AKey);
    end;
  finally
    mRegistry.Free;
  end;
end;

class function TAtlasIdeRegistryAccess.IdeBaseKey: string;
var
  mServices: IOTAServices;
begin
  Result := '';
  if Supports(BorlandIDEServices, IOTAServices, mServices) then
  begin
    Result := mServices.GetBaseRegistryKey;
  end;
  while (Result <> '') and (Result[1] = '\') do
  begin
    Delete(Result, 1, 1);
  end;
end;

end.
