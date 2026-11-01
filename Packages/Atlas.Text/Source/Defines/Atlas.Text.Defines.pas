unit Atlas.Text.Defines;

// Bedingte Symbole des Delphi-Compilers, gemeinsam für Server und Plugin
// (ADR 0012): welche Symbole der Compiler für Plattform und Version selbst
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
  CompilerSymbols: array[0..45] of string = ('CONDITIONALEXPRESSIONS', 'UNICODE', 'NATIVECODE', 'ASSEMBLER',
    'MSWINDOWS', 'WIN32', 'WIN64', 'LINUX', 'LINUX32', 'LINUX64', 'MACOS', 'MACOS32', 'MACOS64', 'IOS', 'IOS32',
    'IOS64', 'IOSSIMULATOR', 'ANDROID', 'ANDROID32', 'ANDROID64', 'POSIX', 'POSIX32', 'POSIX64', 'CPU386', 'CPUX86',
    'CPUX64', 'CPUARM', 'CPUARM32', 'CPUARM64', 'CPU32BITS', 'CPU64BITS', 'LLVM', 'EXTERNALLINKER', 'CONSOLE',
    'BCB', 'DCC', 'ELF', 'PC_MAPPED_EXCEPTIONS', 'PIC', 'UNDERSCOREIMPORTNAME', 'WEAKREF', 'WEAKINSTREF',
    'WEAKINTFREF', 'AUTOREFCOUNT', 'NEXTGEN', 'ALIGN_STACK');

{ TTextDefines }

class function TTextDefines.Predefined(const APlatform: string; ACompilerVersion: Double): TArray<string>;
var
  Platform: string;
  Symbols: TArray<string>;

  procedure Add(const ASymbols: array of string);
  var
    Symbol: string;
  begin
    for Symbol in ASymbols do
    begin
      Symbols := Symbols + [Symbol];
    end;
  end;

begin
  Symbols := nil;
  Add(['CONDITIONALEXPRESSIONS', 'UNICODE', 'NATIVECODE', 'ASSEMBLER']);
  if ACompilerVersion > 0 then
  begin
    Add([Format('VER%d', [Round(ACompilerVersion * 10)])]);
  end;
  Platform := UpperCase(APlatform);
  if (Platform = 'WIN32') or (Platform = '') then
  begin
    Add(['MSWINDOWS', 'WIN32', 'CPUX86', 'CPU386', 'CPU32BITS']);
  end
  else if Platform = 'WIN64' then
  begin
    Add(['MSWINDOWS', 'WIN64', 'CPUX64', 'CPU64BITS']);
  end
  else if Platform = 'WIN64X' then
  begin
    Add(['MSWINDOWS', 'WIN64', 'CPUX64', 'CPU64BITS', 'LLVM']);
  end
  else if Platform = 'LINUX64' then
  begin
    Add(['LINUX', 'LINUX64', 'POSIX', 'POSIX64', 'CPUX64', 'CPU64BITS']);
  end
  else if (Platform = 'OSX64') or (Platform = 'OSXARM64') then
  begin
    Add(['MACOS', 'MACOS64', 'POSIX', 'POSIX64', 'CPU64BITS']);
    if Platform = 'OSX64' then
    begin
      Add(['CPUX64']);
    end
    else
    begin
      Add(['CPUARM64']);
    end;
  end
  else if Platform = 'ANDROID' then
  begin
    Add(['ANDROID', 'ANDROID32', 'LINUX', 'POSIX', 'POSIX32', 'CPUARM', 'CPUARM32', 'CPU32BITS']);
  end
  else if Platform = 'ANDROID64' then
  begin
    Add(['ANDROID', 'ANDROID64', 'LINUX', 'POSIX', 'POSIX64', 'CPUARM', 'CPUARM64', 'CPU64BITS']);
  end
  else if Platform = 'IOSDEVICE64' then
  begin
    Add(['IOS', 'IOS64', 'MACOS', 'POSIX', 'POSIX64', 'CPUARM', 'CPUARM64', 'CPU64BITS']);
  end
  else if Platform = 'IOSSIMARM64' then
  begin
    Add(['IOS', 'IOS64', 'IOSSIMULATOR', 'MACOS', 'POSIX', 'POSIX64', 'CPUARM', 'CPUARM64', 'CPU64BITS']);
  end;
  Result := Symbols;
end;

class function TTextDefines.CompilerVersionOfBds(ABdsVersion: Double): Double;
begin
  if ABdsVersion >= 37 then
  begin
    Result := ABdsVersion;
  end
  else if ABdsVersion >= 8 then
  begin
    Result := ABdsVersion + 13;
  end
  else
  begin
    Result := 0;
  end;
end;

class function TTextDefines.IsCompilerSymbol(const ASymbol: string): Boolean;
var
  Name, Digits: string;
  Number: Integer;
  Symbol: string;
begin
  Name := UpperCase(Trim(ASymbol));
  if Name = '' then
  begin
    Exit(False);
  end;
  // VER80 bis VER370 und künftige Versionen.
  if (Length(Name) > 3) and (Copy(Name, 1, 3) = 'VER') then
  begin
    Digits := Copy(Name, 4, MaxInt);
    if TryStrToInt(Digits, Number) and (Number > 0) then
    begin
      Exit(True);
    end;
  end;
  for Symbol in CompilerSymbols do
  begin
    if Symbol = Name then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

end.
