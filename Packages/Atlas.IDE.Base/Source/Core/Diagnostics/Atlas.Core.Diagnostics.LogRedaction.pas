unit Atlas.Core.Diagnostics.LogRedaction;

// Anonymes Plugin-Protokoll (atlas.log, #1478), ohne VCL und Open Tools API.
// Die Stelle, an der eine Zeile entsteht, kennzeichnet Namen, Pfade und
// fremden Text (Atlas.Text.LogMarks); Redact ersetzt sie vor dem Schreiben:
// - Name zu name#N, Pfad zu datei#N mit Endung, Text zu text#N. Gleiche Werte
//   bekommen im Lauf dieselbe Nummer, damit Zeilen zusammen lesbar bleiben.
//   Nach MaxLabels verschiedenen Werten gibt es nur noch <name>, <datei> und
//   <text> (der Speicher wächst nicht ohne Grenze).
// - Danach als Netz für Zeilen ohne Kennzeichen: absolute Pfade zu <pfad>,
//   Benutzer-, Rechner- und Domänenname zu <benutzer> (Atlas.Text.Anonymize).
// Mit Names (Einstellung diagnostics.log.names, Vorgabe aus) schreibt das
// Protokoll Klarnamen; dann entfallen nur die Kennzeichen. Threadsicher.

interface

uses
  System.SysUtils,
  System.SyncObjs,
  System.Generics.Collections,
  Atlas.Text.LogMarks;

type
  TAtlasLogRedactor = class
  public const
    MaxLabels = 4096;
  private
    FLock: TCriticalSection;
    FLabels: TDictionary<string, Integer>;
    FIdentity: TArray<string>;
    FNames: Boolean;
    function LabelOf(AKind: TLogMarkKind; const AValue: string): string;
    function GetNames: Boolean;
    procedure SetNames(AValue: Boolean);
  public
    /// <summary>AIdentity: Benutzer-, Rechner- und Domänenname; Einträge unter drei Zeichen zählen nicht.</summary>
    constructor Create(const AIdentity: TArray<string>);
    destructor Destroy; override;
    /// <summary>AText ohne Namen, Pfade und fremden Text; mit Names nur ohne Kennzeichen.</summary>
    function Redact(const AText: string): string;
    /// <summary>Vergisst alle Nummern; der nächste Wert bekommt wieder die 1. Die Tabelle lebt sonst so lange wie
    /// das Protokoll (beim Plugin bis zum Entladen). Für Tests: Der Leckmonitor setzt das gemeinsame Protokoll so
    /// nach jedem Test zurück, sonst zählt jeder neue Wert als Leck des Tests, der ihn zuerst schreibt.</summary>
    procedure Forget;
    /// <summary>Benutzer-, Rechner- und Domänenname aus der Umgebung (USERNAME, COMPUTERNAME, USERDOMAIN).
    /// </summary>
    class function EnvironmentIdentity: TArray<string>; static;
    /// <summary>Klarnamen schreiben (diagnostics.log.names).</summary>
    property Names: Boolean read GetNames write SetNames;
  end;

implementation

uses
  Atlas.Text.Anonymize;

const
  cPrefixes: array[TLogMarkKind] of string = ('name#', 'datei#', 'text#');
  cFallbacks: array[TLogMarkKind] of string = (TTextAnonymizer.NameLabel, TTextAnonymizer.FileLabel,
    TTextAnonymizer.TextLabel);

constructor TAtlasLogRedactor.Create(const AIdentity: TArray<string>);
var
  mName: string;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FLabels := TDictionary<string, Integer>.Create;
  FIdentity := nil;
  for mName in AIdentity do
  begin
    if Length(Trim(mName)) >= 3 then
    begin
      FIdentity := FIdentity + [Trim(mName)];
    end;
  end;
end;

destructor TAtlasLogRedactor.Destroy;
begin
  FLabels.Free;
  FLock.Free;
  inherited;
end;

class function TAtlasLogRedactor.EnvironmentIdentity: TArray<string>;
begin
  Result := [GetEnvironmentVariable('USERNAME'), GetEnvironmentVariable('COMPUTERNAME'),
    GetEnvironmentVariable('USERDOMAIN')];
end;

function TAtlasLogRedactor.GetNames: Boolean;
begin
  FLock.Enter;
  try
    Result := FNames;
  finally
    FLock.Leave;
  end;
end;

procedure TAtlasLogRedactor.SetNames(AValue: Boolean);
begin
  FLock.Enter;
  try
    FNames := AValue;
  finally
    FLock.Leave;
  end;
end;

function TAtlasLogRedactor.LabelOf(AKind: TLogMarkKind; const AValue: string): string;
var
  mKey: string;
  mNumber: Integer;
begin
  mKey := TLogMarks.KindChars[AKind] + AnsiLowerCase(Trim(AValue));
  if not FLabels.TryGetValue(mKey, mNumber) then
  begin
    if FLabels.Count >= MaxLabels then
    begin
      mNumber := 0;
    end
    else
    begin
      mNumber := FLabels.Count + 1;
      FLabels.Add(mKey, mNumber);
    end;
  end;
  if mNumber = 0 then
  begin
    Result := cFallbacks[AKind];
  end
  else
  begin
    Result := cPrefixes[AKind] + IntToStr(mNumber);
  end;
  if AKind = TLogMarkKind.Path then
  begin
    Result := Result + TTextAnonymizer.FileExtension(Trim(AValue));
  end;
end;

procedure TAtlasLogRedactor.Forget;
begin
  FLock.Enter;
  try
    FLabels.Clear;
  finally
    FLock.Leave;
  end;
end;

function TAtlasLogRedactor.Redact(const AText: string): string;
begin
  FLock.Enter;
  try
    if FNames then
    begin
      Exit(TLogMarks.Plain(AText));
    end;
    Result := TLogMarks.Resolve(AText,
      function(AKind: TLogMarkKind; const AValue: string): string
      begin
        Result := LabelOf(AKind, AValue);
      end);
    Result := TTextAnonymizer.AnonymizePaths(Result, nil, FIdentity);
  finally
    FLock.Leave;
  end;
end;

end.
