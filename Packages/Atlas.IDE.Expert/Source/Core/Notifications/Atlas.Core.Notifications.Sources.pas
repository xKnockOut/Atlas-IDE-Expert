unit Atlas.Core.Notifications.Sources;

// Quellen der Benachrichtigungszentrale (#601) und die Einstellung
// notifications.sources, ohne VCL: bekannte Kennungen in fester Reihenfolge
// (für Optionsseite und Filter) und die Liste „Quelle=Verhalten“ als Text,
// z. B. "shortcutTips=collect, server=off". Show ist die Vorgabe und steht nie
// in der Liste; unbekannte Quellen bleiben erhalten (künftige Hinweise),
// unbekannte Verhalten werden übergangen.

interface

uses
  System.SysUtils,
  Atlas.Core.Notifications.Contract;

type
  /// <summary>Verhalten einer Quelle aus notifications.sources.</summary>
  TAtlasNotificationSourceMode = record
    Source: string;
    Mode: TAtlasNotificationMode;
  end;

  TAtlasNotificationSources = class
  public const
    /// <summary>Build fertig (#535): Ergebnis eines Builds des Benutzers.</summary>
    Build = 'build';
    /// <summary>Extern geänderte Dateien neu geladen (#536).</summary>
    Reload = 'reload';
    /// <summary>Server neu gestartet (#393) und Meldungen des Servers.</summary>
    Server = 'server';
    /// <summary>Tastenkürzel-Tipps (#600).</summary>
    ShortcutTips = 'shortcutTips';
    /// <summary>Compilerprüfung im Hintergrund (#548).</summary>
    Check = 'check';
    /// <summary>Build-Server (#763): Build auf dem Server ist rot geworden.</summary>
    BuildServer = 'buildServer';
    /// <summary>Bauen beim Öffnen eines Projekts (build.onOpen): Ergebnis des Laufs.</summary>
    OpenBuild = 'openBuild';
    /// <summary>Ausblenden direkt am Element (#628): „Ausgeblendet · Rückgängig“.</summary>
    Hidden = 'hidden';
  public
    /// <summary>Bekannte Quellen in fester Reihenfolge (Optionsseite, Filter).</summary>
    class function Known: TArray<string>; static;
    /// <summary>"show", "collect" bzw. "off".</summary>
    class function ModeName(AMode: TAtlasNotificationMode): string; static;
    /// <summary>Verhalten aus seinem Namen (ohne Groß-/Kleinschreibung); False bei unbekanntem Namen.</summary>
    class function TryMode(const AName: string; out AMode: TAtlasNotificationMode): Boolean; static;
    /// <summary>Paare aus "quelle=verhalten", getrennt durch Komma, Semikolon oder Zeilenumbruch; Leerraum egal.
    /// Spätere Angaben derselben Quelle gewinnen; Einträge ohne Quelle oder mit unbekanntem Verhalten fallen weg.
    /// </summary>
    class function Parse(const ASpec: string): TArray<TAtlasNotificationSourceMode>; static;
    /// <summary>Text für die Einstellung: "quelle=verhalten" mit ", " getrennt, ohne Show.</summary>
    class function ToText(const AModes: TArray<TAtlasNotificationSourceMode>): string; static;
    /// <summary>Verhalten von ASource in ASpec; Show ohne Angabe.</summary>
    class function ModeIn(const ASpec, ASource: string): TAtlasNotificationMode; static;
    /// <summary>ASpec mit AMode für ASource; die übrigen Angaben bleiben in ihrer Reihenfolge.</summary>
    class function WithMode(const ASpec, ASource: string; AMode: TAtlasNotificationMode): string; static;
    /// <summary>Normalisierte Fassung von ASpec (Parse, dann ToText).</summary>
    class function Normalize(const ASpec: string): string; static;
  end;

implementation

{ TAtlasNotificationSources }

class function TAtlasNotificationSources.Known: TArray<string>;
begin
  Result := [Build, Check, Reload, Server, ShortcutTips, BuildServer, OpenBuild, Hidden];
end;

class function TAtlasNotificationSources.ModeName(AMode: TAtlasNotificationMode): string;
begin
  case AMode of
    TAtlasNotificationMode.Collect:
      Result := 'collect';
    TAtlasNotificationMode.Off:
      Result := 'off';
  else
    Result := 'show';
  end;
end;

class function TAtlasNotificationSources.TryMode(const AName: string; out AMode: TAtlasNotificationMode): Boolean;
var
  Name: string;
begin
  Name := LowerCase(Trim(AName));
  Result := True;
  if Name = 'collect' then
    AMode := TAtlasNotificationMode.Collect
  else if Name = 'off' then
    AMode := TAtlasNotificationMode.Off
  else
  begin
    AMode := TAtlasNotificationMode.Show;
    Result := Name = 'show';
  end;
end;

class function TAtlasNotificationSources.Parse(const ASpec: string): TArray<TAtlasNotificationSourceMode>;
var
  Parts: TArray<string>;
  Part, Source: string;
  Equals, Index, Found: Integer;
  Mode: TAtlasNotificationMode;
  Entry: TAtlasNotificationSourceMode;
begin
  Result := nil;
  Parts := ASpec.Split([',', ';', #13, #10]);
  for Part in Parts do
  begin
    Equals := Pos('=', Part);
    if Equals <= 0 then
      Continue;
    Source := Trim(Copy(Part, 1, Equals - 1));
    if (Source = '') or not TryMode(Copy(Part, Equals + 1, MaxInt), Mode) then
      Continue;
    Found := -1;
    for Index := 0 to High(Result) do
      if SameText(Result[Index].Source, Source) then
        Found := Index;
    if Found >= 0 then
    begin
      Result[Found].Mode := Mode;
      Continue;
    end;
    Entry.Source := Source;
    Entry.Mode := Mode;
    Result := Result + [Entry];
  end;
end;

class function TAtlasNotificationSources.ToText(const AModes: TArray<TAtlasNotificationSourceMode>): string;
var
  Entry: TAtlasNotificationSourceMode;
begin
  Result := '';
  for Entry in AModes do
  begin
    if (Entry.Mode = TAtlasNotificationMode.Show) or (Trim(Entry.Source) = '') then
      Continue;
    if Result <> '' then
      Result := Result + ', ';
    Result := Result + Trim(Entry.Source) + '=' + ModeName(Entry.Mode);
  end;
end;

class function TAtlasNotificationSources.ModeIn(const ASpec, ASource: string): TAtlasNotificationMode;
var
  Entry: TAtlasNotificationSourceMode;
begin
  Result := TAtlasNotificationMode.Show;
  for Entry in Parse(ASpec) do
    if SameText(Entry.Source, ASource) then
      Result := Entry.Mode;
end;

class function TAtlasNotificationSources.WithMode(const ASpec, ASource: string;
  AMode: TAtlasNotificationMode): string;
var
  Modes: TArray<TAtlasNotificationSourceMode>;
  Index: Integer;
  Found: Boolean;
  Entry: TAtlasNotificationSourceMode;
begin
  Modes := Parse(ASpec);
  Found := False;
  for Index := 0 to High(Modes) do
    if SameText(Modes[Index].Source, ASource) then
    begin
      Modes[Index].Mode := AMode;
      Found := True;
    end;
  if not Found and (Trim(ASource) <> '') then
  begin
    Entry.Source := Trim(ASource);
    Entry.Mode := AMode;
    Modes := Modes + [Entry];
  end;
  Result := ToText(Modes);
end;

class function TAtlasNotificationSources.Normalize(const ASpec: string): string;
begin
  Result := ToText(Parse(ASpec));
end;

end.
