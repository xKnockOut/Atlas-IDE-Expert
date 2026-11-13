unit Atlas.Core.Debug.Modules;

// Modul der Fehleradresse (#1820), ohne VCL und Open Tools API:
//   - TAtlasDebugFault liest aus der Meldung einer Zugriffsverletzung die Adresse des Codes und, wenn die RTL
//     ihn nennt, den Modulnamen: „Zugriffsverletzung bei Adresse 0040ABCD in Modul 'Project1.exe'. Lesen von
//     Adresse 0000001C“, „Access violation at address … in module '…'“ und der Text des Debuggers bei einer
//     Exception des Betriebssystems („access violation at 0x0040abcd: read of address 0x0000001c“).
//   - TAtlasDebugModuleMap ordnet eine Adresse dem geladenen Modul zu (Basisadresse und Größe aus dem Prozess;
//     nachgeladene DLLs zählen, weil die IDE-Schicht die Liste beim Halt neu liest) und stuft es ein: das
//     Programm selbst, RTL/VCL (Pakete der Delphi-Installation bzw. deren Laufzeitpakete), Windows oder
//     Fremdmodul. Ohne Adressbereich hilft der Name aus der Meldung, sonst der oberste Rahmen ohne Quelltext
//     („:7714C3E2 KERNELBASE.RaiseException + 0x62“).
//   - Resolve fasst das für die Erklärung zusammen: Modul, Einstufung, „keine Debug-Infos“ (Fremdmodul und der
//     oberste Rahmen ohne Quelltext) und die letzte eigene Stelle im Aufrufstapel.

interface

uses
  Atlas.Core.Debug.CallStack;

type
  {$SCOPEDENUMS ON}
  /// <summary>Einstufung eines Moduls: unbekannt, das Programm selbst, RTL/VCL, Windows, Fremdmodul.</summary>
  TAtlasDebugModuleKind = (Unknown, ProgramFile, Runtime, OperatingSystem, Foreign);
  {$SCOPEDENUMS OFF}

  TAtlasDebugLoadedModule = record
    /// <summary>Dateiname ohne Pfad (vcl290.bpl).</summary>
    Name: string;
    /// <summary>Vollständiger Pfad; '' = nur der Name ist bekannt.</summary>
    FileName: string;
    Base: UInt64;
    /// <summary>Größe im Speicher; 0 = Bereich unbekannt.</summary>
    Size: UInt64;
    class function Create(const AFileName: string; ABase, ASize: UInt64): TAtlasDebugLoadedModule; static;
    function Contains(AAddress: UInt64): Boolean;
  end;

  TAtlasDebugModuleList = TArray<TAtlasDebugLoadedModule>;

  /// <summary>Wo das Programm und die Installationen liegen (für die Einstufung).</summary>
  TAtlasDebugModuleEnvironment = record
    /// <summary>Hauptmodul des Prozesses (vollständiger Pfad oder Name).</summary>
    ProgramFile: string;
    /// <summary>Ordner der Delphi-Installation ($(BDS)); '' = unbekannt.</summary>
    BdsDir: string;
    /// <summary>Windows-Ordner; '' = unbekannt.</summary>
    WindowsDir: string;
  end;

  /// <summary>Was die Meldung einer Zugriffsverletzung über den Ort des Fehlers sagt.</summary>
  TAtlasDebugFault = record
    CodeAddressKnown: Boolean;
    /// <summary>Adresse des Codes, der zugegriffen hat.</summary>
    CodeAddress: UInt64;
    /// <summary>Modul laut Meldung der RTL; '' ohne.</summary>
    ModuleName: string;
    class function Parse(const AMessage: string): TAtlasDebugFault; static;
  end;

  TAtlasDebugFaultModule = record
    Known: Boolean;
    Name: string;
    FileName: string;
    Kind: TAtlasDebugModuleKind;
    /// <summary>Fremdmodul, und am Fehler steht kein Quelltext.</summary>
    NoDebugInfo: Boolean;
    /// <summary>Index des letzten durchlaufenen eigenen Rahmens mit Quelltext (von oben der erste); -1 ohne.
    /// </summary>
    OwnFrame: Integer;
  end;

  TAtlasDebugModuleMap = record
  public
    /// <summary>Modul, in dessen Bereich AAddress liegt; -1 ohne.</summary>
    class function IndexOfAddress(const AModules: TAtlasDebugModuleList; AAddress: UInt64): Integer; static;
    /// <summary>Modul mit dem Namen AName (mit oder ohne Endung, Groß/klein egal); -1 ohne.</summary>
    class function IndexOfName(const AModules: TAtlasDebugModuleList; const AName: string): Integer; static;
    /// <summary>Modul aus der Kopfzeile eines Rahmens ohne Symbole („:7714C3E2 KERNELBASE.RaiseException“);
    /// -1, wenn die Kopfzeile kein bekanntes Modul nennt.</summary>
    class function IndexOfHeader(const AModules: TAtlasDebugModuleList; const AHeader: string): Integer; static;
    /// <summary>Laufzeitpaket der Delphi-Installation am Namen (rtl290.bpl, vclwinx290.bpl, fmx290.bpl …)?</summary>
    class function IsRuntimePackageName(const AName: string): Boolean; static;
    /// <summary>Bekannte Systembibliothek am Namen (ntdll.dll, kernel32.dll …)?</summary>
    class function IsSystemName(const AName: string): Boolean; static;
    class function Classify(const AModule: TAtlasDebugLoadedModule;
      const AEnvironment: TAtlasDebugModuleEnvironment): TAtlasDebugModuleKind; static;
    /// <summary>Modul der Fehleradresse aus Meldung, Aufrufstapel (eigene Rahmen gesetzt) und Modulliste.
    /// </summary>
    class function Resolve(const AMessage: string; const AFrames: TAtlasDebugFrames;
      const AModules: TAtlasDebugModuleList;
      const AEnvironment: TAtlasDebugModuleEnvironment): TAtlasDebugFaultModule; static;
  end;

implementation

uses
  System.SysUtils;

const
  /// <summary>Höchstens so viele Hexziffern hat eine Adresse (64 Bit).</summary>
  cMaxHexDigits = 16;
  cHexBase = 16;
  /// <summary>Ziffern der Paketversion am Ende eines Laufzeitpakets (vcl290).</summary>
  cVersionDigits = 3;
  /// <summary>Anfänge der Laufzeitpakete von Delphi; danach folgen Buchstaben und die Paketversion (290).
  /// </summary>
  cRuntimePrefixes: array[0..21] of string = ('rtl', 'vcl', 'fmx', 'dbrtl', 'dbx', 'dsnap', 'soap', 'xmlrtl',
    'inet', 'indy', 'bindcomp', 'bindengine', 'firedac', 'fmxase', 'emsclient', 'restcomponents', 'tethering',
    'ibx', 'adortl', 'cloudservice', 'bdertl', 'designide');
  cSystemNames: array[0..23] of string = ('ntdll', 'kernel32', 'kernelbase', 'user32', 'gdi32', 'gdi32full',
    'win32u', 'advapi32', 'ole32', 'oleaut32', 'combase', 'rpcrt4', 'shell32', 'shlwapi', 'comctl32', 'comdlg32',
    'msvcrt', 'ucrtbase', 'sechost', 'ws2_32', 'winmm', 'uxtheme', 'imm32', 'version');

function LowerName(const AName: string): string;
begin
  Result := LowerCase(Trim(AName));
end;

function WithoutExtension(const AName: string): string;
begin
  Result := ChangeFileExt(LowerName(AName), '');
end;

/// <summary>Liegt APath unter ADir (beide mit \ oder /, Groß/klein egal)? '' nie.</summary>
function IsUnder(const APath, ADir: string): Boolean;
var
  mPath, mDir: string;
begin
  Result := False;
  if (Trim(APath) = '') or (Trim(ADir) = '') then
  begin
    Exit;
  end;
  mPath := LowerCase(StringReplace(Trim(APath), '/', '\', [rfReplaceAll]));
  mDir := LowerCase(StringReplace(Trim(ADir), '/', '\', [rfReplaceAll]));
  if mDir[Length(mDir)] <> '\' then
  begin
    mDir := mDir + '\';
  end;
  Result := Copy(mPath, 1, Length(mDir)) = mDir;
end;

function HexDigit(ACh: Char; out AValue: Integer): Boolean;
begin
  Result := True;
  case ACh of
    '0'..'9':
      AValue := Ord(ACh) - Ord('0');
    'a'..'f':
      AValue := Ord(ACh) - Ord('a') + 10;
    'A'..'F':
      AValue := Ord(ACh) - Ord('A') + 10;
  else
    begin
      AValue := 0;
      Result := False;
    end;
  end;
end;

/// <summary>Hexzahl ab APos (Leerzeichen, $ und 0x davor erlaubt), höchstens 16 Stellen; False ohne Ziffer.
/// </summary>
function ReadHexAt(const AText: string; APos: Integer; out AValue: UInt64): Boolean;
var
  mDigits, mDigit: Integer;
begin
  AValue := 0;
  mDigits := 0;
  while (APos <= Length(AText)) and (AText[APos] = ' ') do
  begin
    Inc(APos);
  end;
  if (APos <= Length(AText)) and (AText[APos] = '$') then
  begin
    Inc(APos);
  end
  else if (APos < Length(AText)) and (AText[APos] = '0') and CharInSet(AText[APos + 1], ['x', 'X']) then
  begin
    Inc(APos, 2);
  end;
  while (APos <= Length(AText)) and (mDigits < cMaxHexDigits) and HexDigit(AText[APos], mDigit) do
  begin
    AValue := AValue * cHexBase + UInt64(mDigit);
    Inc(mDigits);
    Inc(APos);
  end;
  Result := mDigits > 0;
end;

/// <summary>Ist AModule das Programm AProgramFile? Mit Pfad auf beiden Seiten zählt der Pfad, sonst der Name.
/// </summary>
function IsProgram(const AModule: TAtlasDebugLoadedModule; const AProgramFile: string): Boolean;
var
  mProgramName: string;
begin
  if Trim(AProgramFile) = '' then
  begin
    Exit(False);
  end;
  if (AModule.FileName <> '') and (ExtractFilePath(AProgramFile) <> '') then
  begin
    Exit(SameText(Trim(AModule.FileName), Trim(AProgramFile)));
  end;
  mProgramName := LowerName(ExtractFileName(StringReplace(AProgramFile, '/', '\', [rfReplaceAll])));
  Result := LowerName(AModule.Name) = mProgramName;
end;

{ TAtlasDebugLoadedModule }


class function TAtlasDebugLoadedModule.Create(const AFileName: string; ABase, ASize: UInt64): TAtlasDebugLoadedModule;
begin
  Result.FileName := AFileName;
  Result.Name := ExtractFileName(StringReplace(AFileName, '/', '\', [rfReplaceAll]));
  Result.Base := ABase;
  Result.Size := ASize;
end;

function TAtlasDebugLoadedModule.Contains(AAddress: UInt64): Boolean;
begin
  Result := (Size > 0) and (AAddress >= Base) and (AAddress - Base < Size);
end;

{ TAtlasDebugFault }

class function TAtlasDebugFault.Parse(const AMessage: string): TAtlasDebugFault;
const
  // Wörter vor der Adresse des Codes, deutsch und englisch; „Adresse“ bzw. „address“ darf fehlen (Debugger).
  cIntros: array[0..1] of string = ('zugriffsverletzung bei', 'access violation at');
  cAddressWords: array[0..1] of string = ('adresse', 'address');
  cModuleIntros: array[0..1] of string = ('in modul ''', 'in module ''');
var
  mText, mWord: string;
  mAt, mEnd: Integer;
begin
  Result := Default(TAtlasDebugFault);
  mText := LowerCase(AMessage);
  for mWord in cIntros do
  begin
    mAt := Pos(mWord, mText);
    if mAt = 0 then
    begin
      Continue;
    end;
    mAt := mAt + Length(mWord);
    while (mAt <= Length(mText)) and (mText[mAt] = ' ') do
    begin
      Inc(mAt);
    end;
    if Copy(mText, mAt, Length(cAddressWords[0])) = cAddressWords[0] then
    begin
      Inc(mAt, Length(cAddressWords[0]));
    end
    else if Copy(mText, mAt, Length(cAddressWords[1])) = cAddressWords[1] then
    begin
      Inc(mAt, Length(cAddressWords[1]));
    end;
    Result.CodeAddressKnown := ReadHexAt(AMessage, mAt, Result.CodeAddress);
    Break;
  end;
  for mWord in cModuleIntros do
  begin
    mAt := Pos(mWord, mText);
    if mAt = 0 then
    begin
      Continue;
    end;
    mAt := mAt + Length(mWord);
    mEnd := mAt;
    while (mEnd <= Length(AMessage)) and (AMessage[mEnd] <> '''') do
    begin
      Inc(mEnd);
    end;
    Result.ModuleName := Trim(Copy(AMessage, mAt, mEnd - mAt));
    Break;
  end;
end;

{ TAtlasDebugModuleMap }

class function TAtlasDebugModuleMap.IndexOfAddress(const AModules: TAtlasDebugModuleList; AAddress: UInt64): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AModules) do
  begin
    if AModules[mIndex].Contains(AAddress) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

class function TAtlasDebugModuleMap.IndexOfName(const AModules: TAtlasDebugModuleList; const AName: string): Integer;
var
  mIndex: Integer;
  mName, mStem: string;
begin
  mName := LowerName(ExtractFileName(AName));
  mStem := WithoutExtension(mName);
  if mName = '' then
  begin
    Exit(-1);
  end;
  for mIndex := 0 to High(AModules) do
  begin
    if LowerName(AModules[mIndex].Name) = mName then
    begin
      Exit(mIndex);
    end;
  end;
  // Ohne Endung („KERNELBASE“) zählt der Name ohne Endung.
  if mStem = mName then
  begin
    for mIndex := 0 to High(AModules) do
    begin
      if WithoutExtension(AModules[mIndex].Name) = mStem then
      begin
        Exit(mIndex);
      end;
    end;
  end;
  Result := -1;
end;

class function TAtlasDebugModuleMap.IndexOfHeader(const AModules: TAtlasDebugModuleList;
  const AHeader: string): Integer;
var
  mText: string;
  mStop: Integer;
begin
  Result := -1;
  mText := Trim(AHeader);
  // Nur Rahmen ohne Symbole beginnen mit der Adresse: „:7714C3E2 KERNELBASE.RaiseException + 0x62“.
  if (mText = '') or (mText[1] <> ':') then
  begin
    Exit;
  end;
  mStop := Pos(' ', mText);
  if mStop = 0 then
  begin
    Exit;
  end;
  mText := Trim(Copy(mText, mStop + 1, MaxInt));
  mStop := Pos('.', mText);
  if mStop > 1 then
  begin
    // Erst „Modul.Endung“ (Project1.exe), dann nur den Teil vor dem ersten Punkt (KERNELBASE.RaiseException).
    Result := IndexOfName(AModules, Copy(mText, 1, Pos(' ', mText + ' ') - 1));
    if Result < 0 then
    begin
      Result := IndexOfName(AModules, Copy(mText, 1, mStop - 1));
    end;
  end
  else if mText <> '' then
  begin
    Result := IndexOfName(AModules, Copy(mText, 1, Pos(' ', mText + ' ') - 1));
  end;
end;

class function TAtlasDebugModuleMap.IsRuntimePackageName(const AName: string): Boolean;
var
  mName, mPrefix, mRest: string;
  mIndex: Integer;
begin
  Result := False;
  mName := LowerName(ExtractFileName(AName));
  if not SameText(ExtractFileExt(mName), '.bpl') then

  begin
    Exit;
  end;
  mName := ChangeFileExt(mName, '');
  for mPrefix in cRuntimePrefixes do
  begin
    if Copy(mName, 1, Length(mPrefix)) <> mPrefix then
    begin
      Continue;
    end;
    // Hinter dem Anfang Buchstaben, am Ende die Paketversion mit drei Ziffern (vcl290, vclwinx290).
    mRest := Copy(mName, Length(mPrefix) + 1, MaxInt);
    if Length(mRest) < cVersionDigits then
    begin
      Continue;
    end;
    Result := True;
    for mIndex := 1 to Length(mRest) do
    begin
      if mIndex > Length(mRest) - cVersionDigits then
      begin
        Result := Result and CharInSet(mRest[mIndex], ['0'..'9']);
      end
      else
      begin
        Result := Result and CharInSet(mRest[mIndex], ['a'..'z', '_']);
      end;
    end;
    if Result then
    begin
      Exit;
    end;
  end;
end;

class function TAtlasDebugModuleMap.IsSystemName(const AName: string): Boolean;
var
  mStem, mName: string;
begin
  mStem := WithoutExtension(ExtractFileName(AName));
  for mName in cSystemNames do
  begin
    if mStem = mName then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TAtlasDebugModuleMap.Classify(const AModule: TAtlasDebugLoadedModule;
  const AEnvironment: TAtlasDebugModuleEnvironment): TAtlasDebugModuleKind;
begin
  if AModule.Name = '' then
  begin
    Result := TAtlasDebugModuleKind.Unknown;
  end
  else if IsProgram(AModule, AEnvironment.ProgramFile) then
  begin
    Result := TAtlasDebugModuleKind.ProgramFile;
  end
  else if IsUnder(AModule.FileName, AEnvironment.BdsDir) or IsRuntimePackageName(AModule.Name) then
  begin
    Result := TAtlasDebugModuleKind.Runtime;
  end
  else if IsUnder(AModule.FileName, AEnvironment.WindowsDir) or IsSystemName(AModule.Name) then
  begin
    Result := TAtlasDebugModuleKind.OperatingSystem;
  end
  else
  begin
    Result := TAtlasDebugModuleKind.Foreign;
  end;
end;

class function TAtlasDebugModuleMap.Resolve(const AMessage: string; const AFrames: TAtlasDebugFrames;
  const AModules: TAtlasDebugModuleList;
  const AEnvironment: TAtlasDebugModuleEnvironment): TAtlasDebugFaultModule;
var
  mFault: TAtlasDebugFault;
  mIndex: Integer;
  mModule: TAtlasDebugLoadedModule;
begin
  Result := Default(TAtlasDebugFaultModule);
  Result.OwnFrame := -1;
  for mIndex := 0 to High(AFrames) do
  begin
    if AFrames[mIndex].Own and AFrames[mIndex].HasSource then
    begin
      Result.OwnFrame := mIndex;
      Break;
    end;
  end;
  mFault := TAtlasDebugFault.Parse(AMessage);
  mIndex := -1;
  // 1. Adresse im Bereich eines geladenen Moduls; 2. Name aus der Meldung; 3. oberster Rahmen ohne Symbole.
  if mFault.CodeAddressKnown then
  begin
    mIndex := IndexOfAddress(AModules, mFault.CodeAddress);
  end;
  if (mIndex < 0) and (mFault.ModuleName <> '') then
  begin
    mIndex := IndexOfName(AModules, mFault.ModuleName);
  end;
  if (mIndex < 0) and (Length(AFrames) > 0) and not AFrames[0].HasSource then
  begin
    mIndex := IndexOfHeader(AModules, AFrames[0].Header);
  end;
  if mIndex >= 0 then
  begin
    mModule := AModules[mIndex];
  end
  else if mFault.ModuleName <> '' then
  begin
    mModule := TAtlasDebugLoadedModule.Create(mFault.ModuleName, 0, 0);
    // Nur der Name ist bekannt, kein Pfad.
    mModule.FileName := '';
  end
  else
  begin
    Exit;
  end;
  Result.Known := True;
  Result.Name := mModule.Name;
  Result.FileName := mModule.FileName;
  Result.Kind := Classify(mModule, AEnvironment);
  Result.NoDebugInfo := (Result.Kind = TAtlasDebugModuleKind.Foreign) and
    ((Length(AFrames) = 0) or not AFrames[0].HasSource);
end;

end.
