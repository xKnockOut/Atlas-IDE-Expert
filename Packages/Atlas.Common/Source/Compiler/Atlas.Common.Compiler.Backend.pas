unit Atlas.Common.Compiler.Backend;

// Wahl des Wegs zum Compiler (#261) aus compiler.backend, der erkannten
// Ausgabe der Installation (Atlas.Common.Compiler.Edition) und
// compiler.ideCommand (cc.ps1):
//   auto  CommandLine oder Unknown → dcc; sonst ide, wenn cc.ps1 eingerichtet
//         ist; sonst off mit Grund und Ausweg.
//   dcc   nur der Kommandozeilen-Compiler; ohne ihn off.
//   ide   nur über cc.ps1; ohne gültigen Pfad off.
//   off   nie.
// Der Weg über die IDE startet eine eigene IDE und ist deshalb langsam: Er
// läuft nur auf den Befehl „Projekt kompilieren“ (atlas.server.compile), nie
// nach dem Speichern (RunsOnSave). Grund, Ausweg und Statuszeile („Compiler:
// nicht verfügbar (Starter Edition)“) kommen von hier, damit Meldung, Status
// (#28) und die Antwort des Befehls dasselbe sagen.

interface

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Compiler.Edition;

type
  {$SCOPEDENUMS ON}
  TCompilerBackend = (Dcc, Ide, Off);
  {$SCOPEDENUMS OFF}

  TCompilerBackendChoice = record
    Backend: TCompilerBackend;
    /// <summary>Warum kein Compiler nutzbar ist; '' bei Dcc und Ide.</summary>
    Reason: string;
    /// <summary>Was der Benutzer tun kann; '' bei Dcc und Ide.</summary>
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
    /// <summary>"auto", "dcc", "ide", "off".</summary>
    class function SettingText(ASetting: TCompilerBackendSetting): string; static;
    /// <summary>"dcc", "ide", "off".</summary>
    class function BackendText(ABackend: TCompilerBackend): string; static;
    /// <summary>Wählt den Weg. AIdeCommand: compiler.ideCommand ('' = nicht eingerichtet), AIdeCommandExists:
    /// die Datei gibt es.</summary>
    class function Choose(ASetting: TCompilerBackendSetting; AEdition: TCompilerEdition; const AIdeCommand: string;
      AIdeCommandExists: Boolean): TCompilerBackendChoice; static;
    /// <summary>Kompiliert der Weg auch nach dem Speichern? Nur dcc; die IDE nur auf den Befehl.</summary>
    class function RunsOnSave(ABackend: TCompilerBackend): Boolean; static;
    /// <summary>Statuszeile, solange noch nichts geprüft ist.</summary>
    class function UncheckedStatus: string; static;
  end;

implementation

const
  SettingTexts: array[TCompilerBackendSetting] of string = ('auto', 'dcc', 'ide', 'off');
  BackendTexts: array[TCompilerBackend] of string = ('dcc', 'ide', 'off');
  IdeRemedy = 'In RAD Studio mit dem Atlas-Plugin kompilieren (die Meldungen kommen dann aus der IDE) oder ' +
    'in settings.json "compiler.ideCommand" auf cc.ps1 setzen; Atlas baut dann über eine eigene IDE.';

{ TCompilerBackendChoice }

function TCompilerBackendChoice.Usable: Boolean;
begin
  Result := Backend <> TCompilerBackend.Off;
end;

function TCompilerBackendChoice.StatusText: string;
begin
  case Backend of
    TCompilerBackend.Dcc:
      Result := 'Compiler: dcc (Kommandozeile)';
    TCompilerBackend.Ide:
      Result := 'Compiler: IDE über cc.ps1 (nur auf den Befehl „Projekt kompilieren“)';
  else
    Result := 'Compiler: nicht verfügbar (' + Short + ')';
  end;
end;

function TCompilerBackendChoice.MessageText: string;
begin
  if Usable then
    Exit('');
  Result := 'Atlas kann nicht kompilieren: ' + Reason + '.';
  if Remedy <> '' then
    Result := Result + ' ' + Remedy;
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
  Result := SettingTexts[ASetting];
end;

class function TCompilerBackends.BackendText(ABackend: TCompilerBackend): string;
begin
  Result := BackendTexts[ABackend];
end;

class function TCompilerBackends.RunsOnSave(ABackend: TCompilerBackend): Boolean;
begin
  Result := ABackend = TCompilerBackend.Dcc;
end;

class function TCompilerBackends.UncheckedStatus: string;
begin
  Result := 'Compiler: noch nicht geprüft';
end;

function Off(const AReason, ARemedy, AShort: string): TCompilerBackendChoice;
begin
  Result := TCompilerBackendChoice.Unavailable(AReason, ARemedy);
  Result.Short := AShort;
end;

function Ide(const AIdeCommand: string; AExists: Boolean; out AChoice: TCompilerBackendChoice): Boolean;
begin
  AChoice := Default(TCompilerBackendChoice);
  if Trim(AIdeCommand) = '' then
  begin
    AChoice := Off('"compiler.ideCommand" ist nicht gesetzt',
      'In settings.json "compiler.ideCommand" auf den Pfad zu cc.ps1 setzen.', 'compiler.ideCommand fehlt');
    Exit(False);
  end;
  if not AExists then
  begin
    AChoice := Off('"compiler.ideCommand" zeigt auf keine vorhandene Datei',
      'Den Pfad zu cc.ps1 in settings.json prüfen.', 'cc.ps1 nicht gefunden');
    Exit(False);
  end;
  AChoice.Backend := TCompilerBackend.Ide;
  Result := True;
end;

class function TCompilerBackends.Choose(ASetting: TCompilerBackendSetting; AEdition: TCompilerEdition;
  const AIdeCommand: string; AIdeCommandExists: Boolean): TCompilerBackendChoice;
var
  ViaIde: TCompilerBackendChoice;
  DccUsable: Boolean;
begin
  Result := Default(TCompilerBackendChoice);
  DccUsable := (AEdition = TCompilerEdition.CommandLine) or (AEdition = TCompilerEdition.Unknown);
  case ASetting of
    TCompilerBackendSetting.Off:
      Result := Off('"compiler.backend" ist "off"',
        'In settings.json "compiler.backend" auf "auto", "dcc" oder "ide" setzen.', 'abgeschaltet');
    TCompilerBackendSetting.Dcc:
      if DccUsable then
        Result.Backend := TCompilerBackend.Dcc
      else
        Result := Off(TCompilerEditions.Describe(AEdition), IdeRemedy, 'Starter Edition');
    TCompilerBackendSetting.Ide:
      Ide(AIdeCommand, AIdeCommandExists, Result);
  else
    if DccUsable then
      Result.Backend := TCompilerBackend.Dcc
    else if Ide(AIdeCommand, AIdeCommandExists, ViaIde) then
      Result := ViaIde
    else if Trim(AIdeCommand) = '' then
      Result := Off(TCompilerEditions.Describe(AEdition), IdeRemedy, 'Starter Edition')
    else
      // cc.ps1 eingetragen, aber nicht da: beides nennen.
      Result := Off(TCompilerEditions.Describe(AEdition) + '; ' + ViaIde.Reason, ViaIde.Remedy, 'Starter Edition');
  end;
end;

end.
