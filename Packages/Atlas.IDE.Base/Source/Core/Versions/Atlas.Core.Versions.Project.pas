unit Atlas.Core.Versions.Project;

// Versionsnummer eines Projekts aus seinen Versionsinformationen (#533, #1455),
// ohne IDE: FileVersion aus VerInfo_Keys, sonst Major.Minor.Release.Build.
// Base: Release-Wächter (Modul Build-Pipeline) und {version} in Kommentaren
// (Modul Tracker) lesen sie, ohne einander zu kennen.

interface

uses
  System.SysUtils;

type
  TAtlasProjectVersion = class
  public
    /// <summary>Wahrheitswert einer Projektoption: true/1/2 bzw. false/0, sonst ADefault (etwa $(…)).</summary>
    class function IsOn(const AValue: string; ADefault: Boolean): Boolean; static;
    /// <summary>Version aus FileVersion in AVersionKeys (VerInfo_Keys), sonst aus AMajor.AMinor.ARelease.ABuild
    /// (Vorgabe 1.0.0.0); '' ohne Versionsinformationen (AIncludeVersionInfo = VerInfo_IncludeVerInfo).</summary>
    class function FromOptions(const AIncludeVersionInfo, AVersionKeys, AMajor, AMinor, ARelease, ABuild: string): string;
      static;
  end;

implementation

class function TAtlasProjectVersion.IsOn(const AValue: string; ADefault: Boolean): Boolean;
var
  mValue: string;
begin
  mValue := LowerCase(Trim(AValue));
  if (mValue = 'true') or (mValue = '1') or (mValue = '2') then
  begin
    Result := True;
  end
  else if (mValue = 'false') or (mValue = '0') then
  begin
    Result := False;
  end
  else
  begin
    Result := ADefault;
  end;
end;

function VersionPart(const AValue, ADefault: string): string;
begin
  Result := Trim(AValue);
  if Result = '' then
  begin
    Result := ADefault;
  end;
end;

class function TAtlasProjectVersion.FromOptions(const AIncludeVersionInfo, AVersionKeys, AMajor, AMinor, ARelease,
  ABuild: string): string;
var
  mPart: string;
begin
  Result := '';
  if not IsOn(AIncludeVersionInfo, False) then
  begin
    Exit;
  end;
  for mPart in AVersionKeys.Split([';']) do
  begin
    if SameText(Trim(Copy(mPart, 1, Pos('=', mPart) - 1)), 'FileVersion') then
    begin
      Result := Trim(Copy(mPart, Pos('=', mPart) + 1, MaxInt));
      // $(…) setzt erst MSBuild ein; dann gelten die Einzelwerte.
      if Pos('$(', Result) > 0 then
      begin
        Result := '';
      end;
      Break;
    end;
  end;
  if Result = '' then
  begin
    Result := VersionPart(AMajor, '1') + '.' + VersionPart(AMinor, '0') + '.' + VersionPart(ARelease, '0') + '.' +
      VersionPart(ABuild, '0');
  end;
end;

end.
