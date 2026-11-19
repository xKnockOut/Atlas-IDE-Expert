unit Atlas.Text.Defines;

// Bedingte Symbole des Delphi-Compilers, gemeinsam für Server und Plugin
//: welche Symbole der Compiler für Plattform und Version selbst
// setzt, die Compilerversion zur BDS-Version der Registry und ob ein Name
// überhaupt ein Symbol des Compilers ist (auf irgendeiner Plattform, in
// irgendeiner Version). Der Server wertet damit $IFDEF aus (Präprozessor),
// das Plugin prüft damit Defines ohne Quelle (#759).

interface

type
  TTextDefines = class
  public
    /// <summary>Vordefinierte Symbole für Plattform und Compilerversion (z. B. Win64, 37.0); '' = Win32,
    /// Version 0 = ohne VERnnn.</summary>
    class function Predefined(const APlatform: string; ACompilerVersion: Double): TArray<string>; static;
    /// <summary>Compilerversion zur BDS-Version der Registry: bis Delphi 12 (BDS 23.0) BDS + 13,
    /// z. B. 23.0 -> 36.0; ab Delphi 13 gleich (37.0). 0 für unbekannte Werte.</summary>
    class function CompilerVersionOfBds(ABdsVersion: Double): Double; static;
    /// <summary>Setzt der Compiler ASymbol auf einer Plattform oder in einer Version selbst (MSWINDOWS, ANDROID,
    /// CPUX64, VER360, CONSOLE, DEBUG …)? Groß-/Kleinschreibung egal.</summary>
    class function IsCompilerSymbol(const ASymbol: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils;

const
  /// <summary>Symbole, die der Compiler je nach Plattform, Projektart oder Option selbst setzt.</summary>
  cCompilerSymbols: array[0..45] of string = ('CONDITIONALEXPRESSIONS', 'UNICODE', 'NATIVECODE', 'ASSEMBLER',
    'MSWINDOWS', 'WIN32', 'WIN64', 'LINUX', 'LINUX32', 'LINUX64', 'MACOS', 'MACOS32', 'MACOS64', 'IOS', 'IOS32',
    'IOS64', 'IOSSIMULATOR', 'ANDROID', 'ANDROID32', 'ANDROID64', 'POSIX', 'POSIX32', 'POSIX64', 'CPU386', 'CPUX86',
    'CPUX64', 'CPUARM', 'CPUARM32', 'CPUARM64', 'CPU32BITS', 'CPU64BITS', 'LLVM', 'EXTERNALLINKER', 'CONSOLE',
    'BCB', 'DCC', 'ELF', 'PC_MAPPED_EXCEPTIONS', 'PIC', 'UNDERSCOREIMPORTNAME', 'WEAKREF', 'WEAKINSTREF',
    'WEAKINTFREF', 'AUTOREFCOUNT', 'NEXTGEN', 'ALIGN_STACK');

type
  /// <summary>Symbole, die der Compiler für eine Plattform setzt (durch Leerzeichen getrennt).</summary>
  TPlatformSymbols = record
    Name: string;
    Symbols: string;
  end;

const
  cPlatformSymbols: array[0..10] of TPlatformSymbols = (
    (Name: ''; Symbols: 'MSWINDOWS WIN32 CPUX86 CPU386 CPU32BITS'),
    (Name: 'WIN32'; Symbols: 'MSWINDOWS WIN32 CPUX86 CPU386 CPU32BITS'),
    (Name: 'WIN64'; Symbols: 'MSWINDOWS WIN64 CPUX64 CPU64BITS'),
    (Name: 'WIN64X'; Symbols: 'MSWINDOWS WIN64 CPUX64 CPU64BITS LLVM'),
    (Name: 'LINUX64'; Symbols: 'LINUX LINUX64 POSIX POSIX64 CPUX64 CPU64BITS'),
    (Name: 'OSX64'; Symbols: 'MACOS MACOS64 POSIX POSIX64 CPU64BITS CPUX64'),
    (Name: 'OSXARM64'; Symbols: 'MACOS MACOS64 POSIX POSIX64 CPU64BITS CPUARM64'),
    (Name: 'ANDROID'; Symbols: 'ANDROID ANDROID32 LINUX POSIX POSIX32 CPUARM CPUARM32 CPU32BITS'),
    (Name: 'ANDROID64'; Symbols: 'ANDROID ANDROID64 LINUX POSIX POSIX64 CPUARM CPUARM64 CPU64BITS'),
    (Name: 'IOSDEVICE64'; Symbols: 'IOS IOS64 MACOS POSIX POSIX64 CPUARM CPUARM64 CPU64BITS'),
    (Name: 'IOSSIMARM64'; Symbols: 'IOS IOS64 IOSSIMULATOR MACOS POSIX POSIX64 CPUARM CPUARM64 CPU64BITS'));

  /// <summary>Ab dieser BDS-Version (Delphi 13) ist die Compilerversion gleich der BDS-Version.</summary>
  cFirstBdsWithSameVersion = 37;
  /// <summary>Erste BDS-Version (Delphi 2005) und Abstand zur Compilerversion davor.</summary>
  cFirstBdsVersion = 8;
  cBdsToCompilerVersion = 13;
  /// <summary>Vorsilbe der Versionssymbole VER80 … VER370.</summary>
  cVersionPrefix = 'VER';

{ TTextDefines }

class function TTextDefines.Predefined(const APlatform: string; ACompilerVersion: Double): TArray<string>;
var
  mPlatform: string;
  mSymbols: TArray<string>;
  mEntry: TPlatformSymbols;

  procedure Add(const ASymbols: array of string);
  var
    mSymbol: string;
  begin
    for mSymbol in ASymbols do
    begin
      mSymbols := mSymbols + [mSymbol];
    end;
  end;

begin
  mSymbols := nil;
  Add(['CONDITIONALEXPRESSIONS', 'UNICODE', 'NATIVECODE', 'ASSEMBLER']);
  if ACompilerVersion > 0 then
  begin
    Add([cVersionPrefix + IntToStr(Round(ACompilerVersion * 10))]);
  end;
  mPlatform := UpperCase(APlatform);
  for mEntry in cPlatformSymbols do
  begin
    if mEntry.Name = mPlatform then
    begin
      Add(mEntry.Symbols.Split([' ']));
      Break;
    end;
  end;
  Result := mSymbols;
end;

class function TTextDefines.CompilerVersionOfBds(ABdsVersion: Double): Double;
begin
  if ABdsVersion >= cFirstBdsWithSameVersion then
  begin
    Result := ABdsVersion;
  end
  else if ABdsVersion >= cFirstBdsVersion then
  begin
    Result := ABdsVersion + cBdsToCompilerVersion;
  end
  else
  begin
    Result := 0;
  end;
end;

class function TTextDefines.IsCompilerSymbol(const ASymbol: string): Boolean;
var
  mName, mDigits: string;
  mNumber: Integer;
  mSymbol: string;
begin
  mName := UpperCase(Trim(ASymbol));
  if mName = '' then
  begin
    Exit(False);
  end;
  // VER80 bis VER370 und künftige Versionen.
  if (Length(mName) > Length(cVersionPrefix)) and mName.StartsWith(cVersionPrefix) then
  begin
    mDigits := Copy(mName, Length(cVersionPrefix) + 1, MaxInt);
    if TryStrToInt(mDigits, mNumber) and (mNumber > 0) then
    begin
      Exit(True);
    end;
  end;
  for mSymbol in cCompilerSymbols do
  begin
    if mSymbol = mName then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

end.
