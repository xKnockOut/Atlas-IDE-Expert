unit Atlas.Core.CodeInsight.Plan;

// Entscheidungen des Code Insight-Managers (Atlas.IDE.CodeInsight.Manager und .Session), ohne Open Tools API:
// welche Zeichen die Code Insight auslösen, welche Dateien Atlas übernimmt, ob der Server geprüft oder gestartet
// wird, ob ein Start ein Neustart nach Absturz ist und in welcher Reihenfolge die Projekte der Gruppe an den Server
// gehen.

{$SCOPEDENUMS ON}

interface

uses
  System.SysUtils;

type
  /// <summary>Was EnsureSession tun soll.</summary>
  TAtlasSessionEnsure = (
    /// <summary>Nicht im Hauptthread, abgebaut oder verschachtelt aus Start bzw. Stopp: nur herausgeben, was läuft.
    /// </summary>
    Nested,
    /// <summary>Sitzung bereit: abgleichen und herausgeben.</summary>
    Ready,
    /// <summary>Server starten.</summary>
    Start,
    /// <summary>Zweimal gleich abgestürzt: kein stiller Neustart.</summary>
    Held);

  /// <summary>Stand des Managers für EnsureSession.</summary>
  TAtlasSessionState = record
    /// <summary>Aufruf im Hauptthread.</summary>
    Main: Boolean;
    /// <summary>Abgebaut, aber von der IDE noch gehalten (#886).</summary>
    ShutDown: Boolean;
    /// <summary>Verschachtelt aus StopSession bzw. StartSession.</summary>
    Stopping: Boolean;
    Starting: Boolean;
    /// <summary>Eine Sitzung läuft bzw. ist bereit.</summary>
    Running: Boolean;
    Ready: Boolean;
    /// <summary>Start nach wiederholtem Absturz angehalten.</summary>
    Held: Boolean;
  end;

  TAtlasCodeInsightPlan = record
  public const
    /// <summary>Abstand der Prüfungen, ob die Server-Exe da ist.</summary>
    cServerCheckMs = 5000;
  public
    /// <summary>Zeichen, bei denen die IDE die Code Insight fragt: #0 Vervollständigung (Strg+Leer), „.“, #2
    /// Browse (Strg+Klick), #3 Symbolhinweis, #1 Parameterhilfe (Strg+Umschalt+Leer), „(“ und „,“, „&lt;“ für
    /// XMLDoc-Tags (#435), „[“ für Mengen (#448).</summary>
    class function AllowsKey(AKey: Char): Boolean; static;
    /// <summary>Zeichen eines Bezeichners für den Editor; beim Vorprüfen auch „.“.</summary>
    class function TokenChars(APreValidating: Boolean): TSysCharSet; static;
    /// <summary>Dateiendungen, die Atlas übernimmt (.pas, .dpr, .dpk, .inc).</summary>
    class function HandlesExtension(const AFileName: string): Boolean; static;
    /// <summary>Schritt von EnsureSession.</summary>
    class function Ensure(const AState: TAtlasSessionState): TAtlasSessionEnsure; static;
    /// <summary>Ergebnis von EnsureSession im Schritt Nested: die laufende Sitzung, im Hauptthread aber keine mehr
    /// nach dem Abbau.</summary>
    class function NestedResult(const AState: TAtlasSessionState): Boolean; static;
    /// <summary>Hat sich der Server selbst beendet (nicht Atlas)? Für „Server neu gestartet“ (#601).</summary>
    class function Crashed(AStopped, AEndedByAtlas: Boolean): Boolean; static;
    /// <summary>Prüfung der Server-Exe fällig: noch nie (AChecked) oder vor mehr als cServerCheckMs (AElapsedMs).
    /// </summary>
    class function ServerCheckDue(AChecked: Boolean; AElapsedMs: Int64): Boolean; static;
    /// <summary>Zahl der Neustarts nach AStarts Starts.</summary>
    class function Restarts(AStarts: Integer): Integer; static;
    /// <summary>Projekte für den Server: das aktive zuerst, wenn es gespeichert ist (AActiveSaved), dann die übrigen
    /// gespeicherten ASaved in ihrer Reihenfolge.</summary>
    class function ProjectOrder(const AActive: string; AActiveSaved: Boolean; const ASaved: TArray<string>):
      TArray<string>; static;
  end;

implementation

{ TAtlasCodeInsightPlan }

class function TAtlasCodeInsightPlan.AllowsKey(AKey: Char): Boolean;
begin
  Result := CharInSet(AKey, [#0, '.', #1, '(', ',', #2, #3, '<', '[']);
end;

class function TAtlasCodeInsightPlan.TokenChars(APreValidating: Boolean): TSysCharSet;
begin
  Result := ['A'..'Z', 'a'..'z', '0'..'9', '_', '&'];
  if APreValidating then
  begin
    Include(Result, '.');
  end;
end;

class function TAtlasCodeInsightPlan.HandlesExtension(const AFileName: string): Boolean;
var
  mExtension: string;
begin
  mExtension := LowerCase(ExtractFileExt(AFileName));
  Result := (mExtension = '.pas') or (mExtension = '.dpr') or (mExtension = '.dpk') or (mExtension = '.inc');
end;

class function TAtlasCodeInsightPlan.Ensure(const AState: TAtlasSessionState): TAtlasSessionEnsure;
begin
  if not AState.Main or AState.ShutDown or AState.Stopping or AState.Starting then
  begin
    Result := TAtlasSessionEnsure.Nested;
  end
  else if AState.Ready then
  begin
    Result := TAtlasSessionEnsure.Ready;
  end
  else if AState.Held then
  begin
    Result := TAtlasSessionEnsure.Held;
  end
  else
  begin
    Result := TAtlasSessionEnsure.Start;
  end;
end;

class function TAtlasCodeInsightPlan.NestedResult(const AState: TAtlasSessionState): Boolean;
begin
  Result := AState.Running and not (AState.Main and AState.ShutDown);
end;

class function TAtlasCodeInsightPlan.Crashed(AStopped, AEndedByAtlas: Boolean): Boolean;
begin
  Result := AStopped and not AEndedByAtlas;
end;

class function TAtlasCodeInsightPlan.ServerCheckDue(AChecked: Boolean; AElapsedMs: Int64): Boolean;
begin
  Result := not AChecked or (AElapsedMs > cServerCheckMs);
end;

class function TAtlasCodeInsightPlan.Restarts(AStarts: Integer): Integer;
begin
  Result := AStarts - 1;
  if Result < 0 then
  begin
    Result := 0;
  end;
end;

class function TAtlasCodeInsightPlan.ProjectOrder(const AActive: string; AActiveSaved: Boolean;
  const ASaved: TArray<string>): TArray<string>;
var
  mFileName: string;
begin
  Result := nil;
  if (AActive <> '') and AActiveSaved then
  begin
    Result := TArray<string>.Create(AActive);
  end;
  for mFileName in ASaved do
  begin
    if not SameText(mFileName, AActive) then
    begin
      Result := Result + [mFileName];
    end;
  end;
end;

end.
