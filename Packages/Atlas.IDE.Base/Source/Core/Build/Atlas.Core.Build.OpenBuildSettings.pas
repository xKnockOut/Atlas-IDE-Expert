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
    if C.IsLetterOrDigit then
      Result := Result + C.ToLower;
end;

class function TAtlasOpenBuildSettings.StripProjectExt(const AFileName: string): string;
var
  Ext: string;
begin
  // Nur Endungen von Projekten: Namen wie "Atlas.IDE.Expert" behalten ihre Punkte.
  Result := AFileName;
  Ext := LowerCase(ExtractFileExt(Result));
  if (Ext = '.dproj') or (Ext = '.dpr') or (Ext = '.dpk') or (Ext = '.groupproj') then
    Result := Copy(Result, 1, Length(Result) - Length(Ext));
end;

class function TAtlasOpenBuildSettings.NameOf(const AFileName: string): string;
var
  Index: Integer;
begin
  Result := AFileName;
  for Index := Length(Result) downto 1 do
    if (Result[Index] = '\') or (Result[Index] = '/') then
    begin
      Result := Copy(Result, Index + 1, MaxInt);
      Break;
    end;
  Result := StripProjectExt(Result);
end;

class function TAtlasOpenBuildSettings.KindOf(const AName: string): TAtlasCompileKind;
var
  Name: string;
begin
  Name := LowerCase(Trim(AName));
  if Name = 'check' then
    Result := TAtlasCompileKind.Check
  else if Name = 'build' then
    Result := TAtlasCompileKind.Build
  else
    Result := TAtlasCompileKind.Make;
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
    Result := TAtlasOpenBuildScope.Active
  else
    Result := TAtlasOpenBuildScope.All;
end;

class function TAtlasOpenBuildSettings.ParseExclude(const AText: string): TArray<string>;
var
  Part, Name: string;
  Known: TDictionary<string, Boolean>;
begin
  Result := nil;
  Known := TDictionary<string, Boolean>.Create;
  try
    for Part in AText.Split([',', ';', #13, #10]) do
    begin
      Name := NameOf(Trim(Part));
      if (Name = '') or Known.ContainsKey(LowerCase(Name)) then
        Continue;
      Known.Add(LowerCase(Name), True);
      Result := Result + [Name];
    end;
  finally
    Known.Free;
  end;
end;

class function TAtlasOpenBuildSettings.NormalizedExclude(const AText: string): string;
begin
  Result := string.Join(', ', ParseExclude(AText));
end;

class function TAtlasOpenBuildSettings.PickTarget(const AWanted: string; const AAvailable: TArray<string>): string;
var
  Wanted, Name: string;
begin
  Result := '';
  Wanted := TargetKey(AWanted);
  if Wanted = '' then
    Exit;
  for Name in AAvailable do
    if TargetKey(Name) = Wanted then
      Exit(Name);
end;

end.
