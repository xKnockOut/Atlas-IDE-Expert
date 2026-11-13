unit Atlas.IDE.Debug.HoverTree;

// Debug-Hover aufklappen und geänderte Werte zeigen (#895) in der IDE:
//   - Decorate (an TAtlasEditorHover.OnDebugTree gehängt): Baum zum Wert unter der Maus (TAtlasHoverTree) und
//     alter Wert aus TAtlasValueChanges. Ausstehende Auswertungen holt Pump der Reihe nach: Werte über
//     TAtlasIdeDebugValues (verzögerte Antworten des Win64-Debuggers füllen die Zeile nach, die IDE wartet nie),
//     Eigenschaften über atlas/expressionCompletion im Hintergrund. Danach zeichnet der Tooltip neu.
//   - Row (an OnDebugRow): Zeile auf- bzw. zuklappen, Getter auswerten, weitere zeigen.
//   - Aktionen neben „Anheften“ und „Ändern …“, für die gewählte Zeile: Kopieren (Wert; mit Umschalt
//     „Ausdruck = Wert“) und Beobachten (Fenster „Auswerten“ von Atlas mit dem Ausdruck).
//   - Halt: Kontext aus Thread und Methode für den Vergleich; Fortsetzen verwirft den Baum, das Ende der Sitzung
//     auch die gemerkten Werte.
// debug.hoverExpand aus: keine Zeilen, keine Aktionen; debug.hoverChanges aus: keine Markierung; beide aus:
// nichts angemeldet. Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  Atlas.Core.Hover.DebugValue,
  Atlas.Core.Debug.HoverTree,
  Atlas.IDE.Hover.DebugValue,
  Atlas.IDE.Debug.Session;

type
  /// <summary>Anfrage AMethod mit AParamsJson im Hintergrund an den laufenden Server; ADone im Hauptthread, nur
  /// solange das Modul angemeldet ist. False = nicht gestartet (kein Server).</summary>
  TAtlasHoverTreeRequestRunner = reference to function(const AMethod, AParamsJson: string;
    const ADone: TProc<string>): Boolean;

  TAtlasIdeDebugHoverTree = class
  public const
    /// <summary>Ids der Aktionen im Debug-Hover.</summary>
    cCopyAction = 895;
    cWatchAction = 8951;
  private type
    TListener = class(TAtlasIdeDebugListener)
    public
      procedure DebugStopped(AStop: TAtlasDebugStop); override;
      procedure DebugResumed; override;
      procedure DebugEnded; override;
    end;
  private class var
    FInstance: TAtlasIdeDebugHoverTree;
  private
    FChanges: TAtlasValueChanges;
    FTree: TAtlasHoverTree;
    FDebug: TAtlasIdeDebugValues;
    FRequest: TAtlasHoverTreeRequestRunner;
    FListener: IAtlasIdeDebugListener;
    FRefresh: TProc;
    FFileName: string;
    FLine: Integer;
    /// <summary>Eine Auswertung bzw. Anfrage läuft; Antworten älterer Generationen (vor Halt, Fortsetzen) zählen
    /// nicht.</summary>
    FBusy: Boolean;
    FGeneration: Integer;
    constructor Create(const ARequest: TAtlasHoverTreeRequestRunner);
    procedure ApplySettings;
    procedure Stopped;
    /// <summary>Baum verwerfen; AEnded: auch die gemerkten Werte (Ende der Sitzung).</summary>
    procedure Forget(AEnded: Boolean);
    /// <summary>Nächste Auswertung starten, wenn keine läuft.</summary>
    procedure Pump;
    procedure Evaluate(const ARequest: TAtlasHoverTreeRequest);
    procedure Ask(const ARequest: TAtlasHoverTreeRequest);
    /// <summary>Antwort angekommen: Tooltip neu zeichnen, weiter mit der nächsten.</summary>
    procedure Answered(AGeneration: Integer);
    /// <summary>Thread und Methode des Halts; '' ohne angehaltenen Prozess.</summary>
    class function Context: string; static;
    class procedure Copy(const AValue: TAtlasDebugValue); static;
  public
    destructor Destroy; override;
    /// <summary>Teil starten; ARequest schickt Anfragen an den laufenden Server (Eigenschaften).</summary>
    class procedure Start(const ARequest: TAtlasHoverTreeRequestRunner); static;
    class procedure Release; static;
    class function Started: Boolean; static;
    /// <summary>debug.hoverExpand oder debug.hoverChanges an (und Atlas an)?</summary>
    class function Enabled: Boolean; static;
    /// <summary>AValue an AFileName, ALine (1-basiert) mit Zeilen und altem Wert; ARefresh, sobald ausstehende
    /// Kinder da sind.</summary>
    class function Decorate(const AValue: TAtlasDebugValue; const AFileName: string; ALine: Integer;
      const ARefresh: TProc): TAtlasDebugValue; static;
    /// <summary>Klick auf Zeile ARow (-1 der Wert selbst).</summary>
    class procedure Row(ARow: Integer); static;
    /// <summary>Kopieren und Beobachten für AValue (die gewählte Zeile).</summary>
    class function Actions(const AValue: TAtlasDebugValue): TArray<TAtlasDebugValueFix>; static;
    /// <summary>Aktion AAction für AValue; False, wenn sie nicht hierher gehört.</summary>
    class function Act(const AValue: TAtlasDebugValue; AAction: Integer): Boolean; static;
  end;

implementation

uses
  Winapi.Windows,
  Vcl.Clipbrd,
  ToolsAPI,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Settings.Plugin,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Debug.Evaluate,
  Atlas.UI.Debug.Strings;

{ TAtlasIdeDebugHoverTree.TListener }

procedure TAtlasIdeDebugHoverTree.TListener.DebugStopped(AStop: TAtlasDebugStop);
begin
  if FInstance <> nil then
  begin
    FInstance.Stopped;
  end;
end;

procedure TAtlasIdeDebugHoverTree.TListener.DebugResumed;
begin
  if FInstance <> nil then
  begin
    FInstance.Forget(False);
  end;
end;

procedure TAtlasIdeDebugHoverTree.TListener.DebugEnded;
begin
  if FInstance <> nil then
  begin
    FInstance.Forget(True);
  end;
end;

{ TAtlasIdeDebugHoverTree }

constructor TAtlasIdeDebugHoverTree.Create(const ARequest: TAtlasHoverTreeRequestRunner);
var
  mTexts: TAtlasHoverTreeTexts;
begin
  inherited Create;
  FRequest := ARequest;
  FChanges := TAtlasValueChanges.Create;
  FTree := TAtlasHoverTree.Create(FChanges);
  FDebug := TAtlasIdeDebugValues.Create;
  mTexts := Default(TAtlasHoverTreeTexts);
  mTexts.Evaluate := TAtlasDebugStrings.Text(TAtlasDebugTextId.HoverTreeEvaluate);
  mTexts.Pending := TAtlasDebugStrings.Text(TAtlasDebugTextId.HoverTreePending);
  mTexts.More := TAtlasDebugStrings.Text(TAtlasDebugTextId.HoverTreeMore);
  FTree.Texts := mTexts;
  ApplySettings;
end;

destructor TAtlasIdeDebugHoverTree.Destroy;
begin
  // Laufende Auswertung verwerfen: ihr Rückruf erreicht das Objekt nicht mehr.
  if FDebug <> nil then
  begin
    FDebug.Cancel;
  end;
  FreeAndNil(FDebug);
  FreeAndNil(FTree);
  FreeAndNil(FChanges);
  FRequest := nil;
  FRefresh := nil;
  inherited Destroy;
end;

procedure TAtlasIdeDebugHoverTree.ApplySettings;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  FTree.MaxChildren := mSettings.DebugHoverMaxChildren;
  FTree.ShowChanges := mSettings.DebugHoverChanges;
end;

class function TAtlasIdeDebugHoverTree.Context: string;
var
  mThread: IOTAThread;
begin
  Result := '';
  mThread := TAtlasIdeDebugValues.StoppedThread;
  if (mThread = nil) or (mThread.GetCallCount < 1) then
  begin
    Exit;
  end;
  try
    // Kopf des obersten Rahmens ohne Argumente: „Unit.TKlasse.Methode“ (Rahmen zählen ab 1).
    Result := mThread.GetCallHeader(1);
    if Pos('(', Result) > 0 then
    begin
      Result := System.Copy(Result, 1, Pos('(', Result) - 1);
    end;
    Result := IntToStr(mThread.OSThreadID) + ':' + Trim(Result);
  except
    // Sitzung beim Lesen beendet ("disconnected session"): ohne Kontext kein Vergleich.
    Result := '';
  end;
end;

procedure TAtlasIdeDebugHoverTree.Stopped;
begin
  Forget(False);
  FChanges.BeginStop(Context);
end;

procedure TAtlasIdeDebugHoverTree.Forget(AEnded: Boolean);
begin
  FDebug.Cancel;
  Inc(FGeneration);
  FBusy := False;
  if AEnded then
  begin
    FTree.Clear;
    FChanges.Clear;
  end
  else
  begin
    FTree.Reset;
  end;
end;

procedure TAtlasIdeDebugHoverTree.Answered(AGeneration: Integer);
begin
  if AGeneration <> FGeneration then
  begin
    Exit;
  end;
  FBusy := False;
  if Assigned(FRefresh) then
  begin
    FRefresh();
  end;
  Pump;
end;

procedure TAtlasIdeDebugHoverTree.Evaluate(const ARequest: TAtlasHoverTreeRequest);
var
  mGeneration: Integer;
  mKey: string;
  mValue: TAtlasDebugValue;
  mDone: TAtlasDebugValueEvent;
begin
  mGeneration := FGeneration;
  mKey := ARequest.Key;
  FBusy := True;
  // Typisierte Variable: Evaluate ist überladen.
  mDone :=
    procedure(const AValue: TAtlasDebugValue)
    begin
      // Verzögert (Win64): Antwort im Hauptthread; nach Release hat FDebug sie verworfen.
      if (FInstance = nil) or (mGeneration <> FInstance.FGeneration) then
      begin
        Exit;
      end;
      FInstance.FTree.SetResult(mKey, AValue.State = TAtlasDebugValueState.Value, AValue.Text);
      FInstance.Answered(mGeneration);
    end;
  mValue := FDebug.Evaluate(ARequest.Expression, FFileName, FLine, ARequest.SideEffects, mDone);
  if mValue.State = TAtlasDebugValueState.Pending then
  begin
    Exit;
  end;
  FTree.SetResult(mKey, mValue.State = TAtlasDebugValueState.Value, mValue.Text);
  FBusy := False;
end;

procedure TAtlasIdeDebugHoverTree.Ask(const ARequest: TAtlasHoverTreeRequest);
var
  mGeneration: Integer;
  mKey: string;
begin
  mGeneration := FGeneration;
  mKey := ARequest.Key;
  FBusy := True;
  if Assigned(FRequest) and FRequest('atlas/expressionCompletion', TAtlasHoverTree.CompletionParams(
    TLspSession.PathToUri(FFileName), FLine - 1, ARequest.Expression),
    procedure(AAnswer: string)
    begin
      if (FInstance = nil) or (mGeneration <> FInstance.FGeneration) then
      begin
        Exit;
      end;
      FInstance.FTree.SetProperties(mKey, TAtlasHoverTree.PropertiesOf(AAnswer));
      FInstance.Answered(mGeneration);
    end) then
  begin
    Exit;
  end;
  // Ohne Server: nur die Felder aus dem Debugger.
  FTree.SetProperties(mKey, nil);
  FBusy := False;
end;

procedure TAtlasIdeDebugHoverTree.Pump;
var
  mRequest, mLast: TAtlasHoverTreeRequest;
begin
  // Sofortige Antworten (Win32) gehen in einer Schleife; verzögerte (Win64) und der Server melden sich später.
  mLast := Default(TAtlasHoverTreeRequest);
  while not FBusy and FTree.NextRequest(mRequest) do
  begin
    // Dieselbe Anfrage noch einmal: Die Antwort hat nichts bewegt, nicht im Kreis fragen.
    if (mRequest.Key = mLast.Key) and (mRequest.Expression = mLast.Expression) then
    begin
      Exit;
    end;
    mLast := mRequest;
    if mRequest.Properties then
    begin
      Ask(mRequest);
    end
    else
    begin
      Evaluate(mRequest);
    end;
  end;
end;

class procedure TAtlasIdeDebugHoverTree.Start(const ARequest: TAtlasHoverTreeRequestRunner);
begin
  if FInstance <> nil then
  begin
    FInstance.ApplySettings;
    Exit;
  end;
  FInstance := TAtlasIdeDebugHoverTree.Create(ARequest);
  FInstance.FListener := TListener.Create;
  TAtlasIdeDebugSession.AddListener(FInstance.FListener);
  TAtlasIdeDebugSession.Start;
end;

class procedure TAtlasIdeDebugHoverTree.Release;
var
  mInstance: TAtlasIdeDebugHoverTree;
begin
  if FInstance = nil then
  begin
    Exit;
  end;
  mInstance := FInstance;
  FInstance := nil;
  if mInstance.FListener <> nil then
  begin
    TAtlasIdeDebugSession.RemoveListener(mInstance.FListener);
  end;
  mInstance.FListener := nil;
  mInstance.Free;
end;

class function TAtlasIdeDebugHoverTree.Started: Boolean;
begin
  Result := FInstance <> nil;
end;

class function TAtlasIdeDebugHoverTree.Enabled: Boolean;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := mSettings.Enabled and (mSettings.DebugHoverExpand or mSettings.DebugHoverChanges);
end;

class function TAtlasIdeDebugHoverTree.Decorate(const AValue: TAtlasDebugValue; const AFileName: string;
  ALine: Integer; const ARefresh: TProc): TAtlasDebugValue;
var
  mSettings: TAtlasPluginSettings;
begin
  Result := AValue;
  if (FInstance = nil) or (AValue.State <> TAtlasDebugValueState.Value) or (AValue.Expression = '') then
  begin
    Exit;
  end;
  mSettings := TAtlasIdeSettings.Current;
  FInstance.ApplySettings;
  FInstance.FRefresh := ARefresh;
  FInstance.FFileName := AFileName;
  FInstance.FLine := ALine;
  if mSettings.DebugHoverExpand then
  begin
    FInstance.FTree.Bind(AValue.Expression, AValue.Text);
    // Erst auswerten: Sofortige Antworten stehen so gleich in den Zeilen.
    FInstance.Pump;
    Result := FInstance.FTree.Decorate(AValue);
  end
  else if mSettings.DebugHoverChanges then
  begin
    Result.OldText := FInstance.FChanges.Observe(AValue.Expression, AValue.Text);
  end;
end;

class procedure TAtlasIdeDebugHoverTree.Row(ARow: Integer);
begin
  if (FInstance <> nil) and FInstance.FTree.Click(ARow) then
  begin
    FInstance.Pump;
  end;
end;

class function TAtlasIdeDebugHoverTree.Actions(const AValue: TAtlasDebugValue): TArray<TAtlasDebugValueFix>;
begin
  Result := nil;
  if (FInstance = nil) or (AValue.State <> TAtlasDebugValueState.Value) or
    not TAtlasIdeSettings.Current.DebugHoverExpand then
  begin
    Exit;
  end;
  Result := [TAtlasDebugValueFix.Create(cCopyAction, TAtlasDebugStrings.Text(TAtlasDebugTextId.HoverTreeCopy))];
  if TAtlasIdeDebugEvaluate.Started then
  begin
    Result := Result + [TAtlasDebugValueFix.Create(cWatchAction,
      TAtlasDebugStrings.Text(TAtlasDebugTextId.HoverTreeWatch))];
  end;
end;

class procedure TAtlasIdeDebugHoverTree.Copy(const AValue: TAtlasDebugValue);
begin
  // Mit Umschalt: „Ausdruck = Wert“.
  if GetKeyState(VK_SHIFT) < 0 then
  begin
    Clipboard.AsText := AValue.Expression + ' = ' + AValue.Text;
  end
  else
  begin
    Clipboard.AsText := AValue.Text;
  end;
end;

class function TAtlasIdeDebugHoverTree.Act(const AValue: TAtlasDebugValue; AAction: Integer): Boolean;
begin
  Result := (FInstance <> nil) and ((AAction = cCopyAction) or (AAction = cWatchAction));
  if not Result then
  begin
    Exit;
  end;
  if AAction = cCopyAction then
  begin
    Copy(AValue);
  end
  else
  begin
    TAtlasIdeDebugEvaluate.ShowWindow(AValue.Expression);
  end;
end;

end.
