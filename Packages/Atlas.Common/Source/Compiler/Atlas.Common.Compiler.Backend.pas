unit Atlas.Common.Compiler.Backend;

// Wahl des Wegs zum Compiler (#261) aus compiler.backend und der erkannten
// Ausgabe der Installation (Atlas.Common.Compiler.Edition):
//   auto  CommandLine oder Unknown → dcc; sonst off mit Grund und Ausweg.
//   dcc   nur der Kommandozeilen-Compiler; ohne ihn off.
//   off   nie.
// Ohne Kommandozeilen-Compiler baut eine laufende RAD Studio mit Atlas
// (Werkzeug build_project); den Weg über eine eigene IDE gibt es seit #1904
// nicht mehr. Grund, Ausweg und Statuszeile („Compiler: nicht verfügbar
// (Starter Edition)“) kommen von hier, damit Meldung, Status (#28) und die
// Antwort des Befehls dasselbe sagen.

interface

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Compiler.Edition;

type
  {$SCOPEDENUMS ON}
  TCompilerBackend = (Dcc, Off);
  {$SCOPEDENUMS OFF}

  TCompilerBackendChoice = record
    Backend: TCompilerBackend;
    /// <summary>Warum kein Compiler nutzbar ist; '' bei Dcc.</summary>
    Reason: string;
    /// <summary>Was der Benutzer tun kann; '' bei Dcc.</summary>
    Remedy: string;
    /// <summary>Kurzform des Grunds für die Statuszeile, z. B. „Starter Edition“.</summary>
    Short: string;
    function Usable: Boolean;
    /// <summary>Zeile für den Status (#28), z. B. „Compiler: dcc (Kommandozeile)“ oder
    /// „Compiler: nicht verfügbar (Starter Edition)“.</summary>
    function StatusText: string;
    /// <summary>Text der einmaligen Meldung und der Antwort des Befehls: Grund und Ausweg.</summary>
    function MessageText: string;
    /// <summary>Nicht nutzbar mit Grund AReason (z. B. Laufzeitfehler); Kurzform = Grund.</summary>
    class function Unavailable(const AReason, ARemedy: string): TCompilerBackendChoice; static;
  end;

  TCompilerBackends = class
  public
    /// <summary>"auto", "dcc", "off".</summary>
    class function SettingText(ASetting: TCompilerBackendSetting): string; static;
    /// <summary>"dcc", "off".</summary>
    class function BackendText(ABackend: TCompilerBackend): string; static;
    /// <summary>Wählt den Weg aus der Einstellung und der erkannten Ausgabe.</summary>
    class function Choose(ASetting: TCompilerBackendSetting;
      AEdition: TCompilerEdition): TCompilerBackendChoice; static;
    /// <summary>Kompiliert der Weg auch nach dem Speichern? Nur dcc.</summary>
    class function RunsOnSave(ABackend: TCompilerBackend): Boolean; static;
    /// <summary>Statuszeile, solange noch nichts geprüft ist.</summary>
    class function UncheckedStatus: string; static;
  end;

implementation

uses
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TBackendText = (CompilerNotAvailable, AtlasCannotCompile, CompilerNotCheckedYet, CompilerBackendIsOff,
    InSettingsJsonSetCompiler, CompilerDccCommandLine, Off, BuildNeedsIdeOrCommandLine);

const
  cTexts: array[TBackendText] of TAtlasText = (
    (De: 'Compiler: nicht verfügbar (%s)'; En: 'Compiler: not available (%s)'),
    (De: 'Atlas kann nicht kompilieren: %s.'; En: 'Atlas cannot compile: %s.'),
    (De: 'Compiler: noch nicht geprüft'; En: 'Compiler: not checked yet'),
    (De: '"compiler.backend" ist "off"'; En: '"compiler.backend" is "off"'),
    (De: 'In settings.json "compiler.backend" auf "auto" oder "dcc" setzen.';
     En: 'In settings.json set "compiler.backend" to "auto" or "dcc".'),
    (De: 'Compiler: dcc (Kommandozeile)'; En: 'Compiler: dcc (command line)'),
    (De: 'abgeschaltet'; En: 'off'),
    (De: 'Bauen braucht eine laufende RAD Studio mit Atlas (Werkzeug build_project) oder einen ' +
      'Kommandozeilen-Compiler.';
     En: 'Building needs a running RAD Studio with Atlas (tool build_project) or a command line compiler.'));

{$SCOPEDENUMS OFF}

const
  cSettingTexts: array[TCompilerBackendSetting] of string = ('auto', 'dcc', 'off');
  cBackendTexts: array[TCompilerBackend] of string = ('dcc', 'off');

{ TCompilerBackendChoice }

function TCompilerBackendChoice.Usable: Boolean;
begin
  Result := Backend <> TCompilerBackend.Off;
end;

function TCompilerBackendChoice.StatusText: string;
begin
  case Backend of
    TCompilerBackend.Dcc:
      Result := cTexts[TBackendText.CompilerDccCommandLine].Text;
  else
    Result := cTexts[TBackendText.CompilerNotAvailable].Fmt([Short]);
  end;
end;

function TCompilerBackendChoice.MessageText: string;
begin
  if Usable then
  begin
    Exit('');
  end;
  Result := cTexts[TBackendText.AtlasCannotCompile].Fmt([Reason]);
  if Remedy <> '' then
  begin
    Result := Result + ' ' + Remedy;
  end;
end;

class function TCompilerBackendChoice.Unavailable(const AReason, ARemedy: string): TCompilerBackendChoice;
begin
  Result := Default(TCompilerBackendChoice);
  Result.Backend := TCompilerBackend.Off;
  Result.Reason := AReason;
  Result.Remedy := ARemedy;
  Result.Short := AReason;
end;

{ TCompilerBackends }

class function TCompilerBackends.SettingText(ASetting: TCompilerBackendSetting): string;
begin
  Result := cSettingTexts[ASetting];
end;

class function TCompilerBackends.BackendText(ABackend: TCompilerBackend): string;
begin
  Result := cBackendTexts[ABackend];
end;

class function TCompilerBackends.RunsOnSave(ABackend: TCompilerBackend): Boolean;
begin
  Result := ABackend = TCompilerBackend.Dcc;
end;

class function TCompilerBackends.UncheckedStatus: string;
begin
  Result := cTexts[TBackendText.CompilerNotCheckedYet].Text;
end;

function Off(const AReason, ARemedy, AShort: string): TCompilerBackendChoice;
begin
  Result := TCompilerBackendChoice.Unavailable(AReason, ARemedy);
  Result.Short := AShort;
end;

class function TCompilerBackends.Choose(ASetting: TCompilerBackendSetting;
  AEdition: TCompilerEdition): TCompilerBackendChoice;
var
  mDccUsable: Boolean;
begin
  Result := Default(TCompilerBackendChoice);
  mDccUsable := (AEdition = TCompilerEdition.CommandLine) or (AEdition = TCompilerEdition.Unknown);
  if ASetting = TCompilerBackendSetting.Off then
  begin
    Result := Off(cTexts[TBackendText.CompilerBackendIsOff].Text,
      cTexts[TBackendText.InSettingsJsonSetCompiler].Text, cTexts[TBackendText.Off].Text);
  end
  else if mDccUsable then
  begin
    Result.Backend := TCompilerBackend.Dcc;
  end
  else
  begin
    Result := Off(TCompilerEditions.Describe(AEdition), cTexts[TBackendText.BuildNeedsIdeOrCommandLine].Text,
      'Starter Edition');
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Compiler.Backend', cTexts);

end.
