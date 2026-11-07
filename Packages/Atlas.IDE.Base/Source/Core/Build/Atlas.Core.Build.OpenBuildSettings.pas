unit Atlas.Core.Build.OpenBuildSettings;

// Werte der Einstellungen „Bauen beim Öffnen“ (build.onOpen…, #1293): Art, Umfang, Wartezeit, Ausschlussliste,
// Konfiguration und Plattform. Im Kern, weil Einstellungen und Optionsdialog sie ohne das Modul Build lesen und
// schreiben (#1455, ADR 0017); der Lauf selbst (`Atlas.Core.Build.OpenBuild`) gehört zum Modul.

interface

{$SCOPEDENUMS ON}

uses
  Atlas.Core.Build.Events;

type
  /// <summary>Welche Projekte einer Projektgruppe gebaut werden (build.onOpenScope).</summary>
  TAtlasOpenBuildScope = (All, Active);

  TAtlasOpenBuildSettings = class
  public const
    DefaultDelayMs = 3000;
    MinDelayMs = 500;
    MaxDelayMs = 60000;
    KindNames: array[0..2] of string = ('check', 'make', 'build');
    ScopeNames: array[TAtlasOpenBuildScope] of string = ('all', 'active');
  public
    /// <summary>AFileName ohne Endung .dproj, .dpr, .dpk bzw. .groupproj; andere Endungen bleiben.</summary>
    class function StripProjectExt(const AFileName: string): string; static;
    /// <summary>Projektname ohne Pfad und Endung (beide Trenner, auch unter Linux).</summary>
    class function NameOf(const AFileName: string): string; static;
    /// <summary>check, make oder build; sonst Make.</summary>
    class function KindOf(const AName: string): TAtlasCompileKind; static;
    class function KindName(AKind: TAtlasCompileKind): string; static;
    class function ScopeOf(const AName: string): TAtlasOpenBuildScope; static;
    /// <summary>Namen aus build.onOpenExclude (Komma, Semikolon oder Zeilenumbruch), ohne Endung und Leerraum.
    /// </summary>
    class function ParseExclude(const AText: string): TArray<string>; static;
    class function NormalizedExclude(const AText: string): string; static;
    /// <summary>Vorgabe AWanted (Konfiguration oder Plattform, #1293) in der Schreibweise aus AAvailable; '' ohne
    /// Vorgabe oder wenn das Projekt sie nicht kennt (dann gilt die Einstellung des Projekts).</summary>
    class function PickTarget(const AWanted: string; const AAvailable: TArray<string>): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.Character,
  System.Generics.Collections;

{ TAtlasOpenBuildSettings }

// Vergleichsschlüssel: nur Buchstaben und Ziffern, damit „Win 64“ oder „win-64“ die Plattform Win64 treffen.
function TargetKey(const AName: string): string;
var
  C: Char;
begin
  Result := '';
  for C in AName do
  begin
    if C.IsLetterOrDigit then
    begin
      Result := Result + C.ToLower;
    end;
  end;
end;

class function TAtlasOpenBuildSettings.StripProjectExt(const AFileName: string): string;
var
  mExt: string;
begin
  // Nur Endungen von Projekten: Namen wie "Atlas.IDE.Expert" behalten ihre Punkte.
  Result := AFileName;
  mExt := LowerCase(ExtractFileExt(Result));
  if (mExt = '.dproj') or (mExt = '.dpr') or (mExt = '.dpk') or (mExt = '.groupproj') then
  begin
    Result := Copy(Result, 1, Length(Result) - Length(mExt));
  end;
end;

class function TAtlasOpenBuildSettings.NameOf(const AFileName: string): string;
var
  mIndex: Integer;
begin
  Result := AFileName;
  for mIndex := Length(Result) downto 1 do
  begin
    if (Result[mIndex] = '\') or (Result[mIndex] = '/') then
    begin
      Result := Copy(Result, mIndex + 1, MaxInt);
      Break;
    end;
  end;
  Result := StripProjectExt(Result);
end;

class function TAtlasOpenBuildSettings.KindOf(const AName: string): TAtlasCompileKind;
var
  mName: string;
begin
  mName := LowerCase(Trim(AName));
  if mName = 'check' then
  begin
    Result := TAtlasCompileKind.Check;
  end
  else if mName = 'build' then
  begin
    Result := TAtlasCompileKind.Build;
  end
  else
  begin
    Result := TAtlasCompileKind.Make;
  end;
end;

class function TAtlasOpenBuildSettings.KindName(AKind: TAtlasCompileKind): string;
begin
  case AKind of
    TAtlasCompileKind.Check:
      Result := KindNames[0];
    TAtlasCompileKind.Build:
      Result := KindNames[2];
  else
    Result := KindNames[1];
  end;
end;

class function TAtlasOpenBuildSettings.ScopeOf(const AName: string): TAtlasOpenBuildScope;
begin
  if SameText(Trim(AName), ScopeNames[TAtlasOpenBuildScope.Active]) then
  begin
    Result := TAtlasOpenBuildScope.Active;
  end
  else
  begin
    Result := TAtlasOpenBuildScope.All;
  end;
end;

class function TAtlasOpenBuildSettings.ParseExclude(const AText: string): TArray<string>;
var
  mPart, mName: string;
  mKnown: TDictionary<string, Boolean>;
begin
  Result := nil;
  mKnown := TDictionary<string, Boolean>.Create;
  try
    for mPart in AText.Split([',', ';', #13, #10]) do
    begin
      mName := NameOf(Trim(mPart));
      if (mName = '') or mKnown.ContainsKey(LowerCase(mName)) then
      begin
        Continue;
      end;
      mKnown.Add(LowerCase(mName), True);
      Result := Result + [mName];
    end;
  finally
    mKnown.Free;
  end;
end;

class function TAtlasOpenBuildSettings.NormalizedExclude(const AText: string): string;
begin
  Result := string.Join(', ', ParseExclude(AText));
end;

class function TAtlasOpenBuildSettings.PickTarget(const AWanted: string; const AAvailable: TArray<string>): string;
var
  mWanted, mName: string;
begin
  Result := '';
  mWanted := TargetKey(AWanted);
  if mWanted = '' then
  begin
    Exit;
  end;
  for mName in AAvailable do
  begin
    if TargetKey(mName) = mWanted then
    begin
      Exit(mName);
    end;
  end;
end;

end.
