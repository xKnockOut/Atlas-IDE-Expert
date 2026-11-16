unit Atlas.Core.Designer.UndoFlow;

// Ablauf von Rückgängig im Formular-Designer (#1887), ohne VCL und Open
// Tools API: Erfassen, Verlauf je Formular, Zurückladen. Die IDE-Schicht
// (TAtlasIdeDesignerUndo) reicht die Benachrichtigungen des Designers als
// TAtlasDesignSurfaceListener herein und reiht das Erfassen ein.
// - Eingefügt, gelöscht, geändert, geöffnet: Erfassen nach dem laufenden
//   Ereignis (OnQueue; dann stehen Lage, Größe und Werte fest). Mehrere
//   Ereignisse vor dem Erfassen ergeben einen Schritt; es gilt der zuletzt
//   gemeldete Designer.
// - Auswahl: nur vor der ersten Änderung, damit der Ausgangsstand bekannt
//   ist.
// - Geschlossen: Verlauf des Formulars weg, ein noch ausstehendes Erfassen
//   für dieses Formular entfällt.
// - Zurückladen (Restore): Plan aus aktuellem und gewünschtem Stand, dann
//   TAtlasDesignerUndoApply; eigene Änderungen dabei erfasst Atlas nicht.
//   Der tatsächlich erreichte Stand gilt, auch wenn nicht alles herstellbar
//   war.
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Atlas.Core.Designer.Undo,
  Atlas.Core.Designer.UndoApply,
  Atlas.Core.Designer.Surface;

type
  /// <summary>Ergebnis von Restore: was nicht herstellbar war.</summary>
  TAtlasUndoOutcome = record
    Failures: TArray<string>;
    MissingMethods: TArray<TAtlasUndoMissingMethod>;
  end;

  TAtlasDesignerUndoFlow = class(TAtlasDesignSurfaceListener)
  private
    /// <summary>Verlauf je Formular (Wurzelkomponente im Designer).</summary>
    FHistories: TObjectDictionary<TComponent, TAtlasFormUndoHistory>;
    /// <summary>Designer, dessen Stand nach dem laufenden Ereignis zu erfassen ist.</summary>
    FPending: IAtlasDesignSurface;
    FQueued: Boolean;
    /// <summary>Atlas lädt gerade zurück: eigene Änderungen nicht erfassen.</summary>
    FBusy: Boolean;
    FEnabled: Boolean;
    FMaxSteps: Integer;
    FWords: TAtlasUndoWords;
    FReasons: TAtlasUndoReasons;
    FOnQueue: TProc;
    procedure Queue(const ASurface: IAtlasDesignSurface);
    function HistoryOf(ARoot: TComponent): TAtlasFormUndoHistory;
    procedure SetEnabled(AValue: Boolean);
  public
    /// <summary>AWords: Texte der Schritte, AReasons: Gründe beim Zurückladen.</summary>
    constructor Create(const AWords: TAtlasUndoWords; const AReasons: TAtlasUndoReasons);
    destructor Destroy; override;
    procedure ItemsChanged(const ASurface: IAtlasDesignSurface); override;
    procedure SelectionChanged(const ASurface: IAtlasDesignSurface); override;
    procedure Opened(const ASurface: IAtlasDesignSurface); override;
    procedure Closed(const ASurface: IAtlasDesignSurface); override;
    /// <summary>Erfasst den Stand des zuletzt gemeldeten Designers; die IDE ruft es nach OnQueue.</summary>
    procedure Capture;
    /// <summary>Verlauf des Formulars in ASurface; False ohne Designer, ohne Formular oder ohne Verlauf.</summary>
    function Active(const ASurface: IAtlasDesignSurface; out AHistory: TAtlasFormUndoHistory): Boolean;
    function CanUndo(const ASurface: IAtlasDesignSurface): Boolean;
    function CanRedo(const ASurface: IAtlasDesignSurface): Boolean;
    /// <summary>Lädt den Stand AIndex des Verlaufs in den Designer; False, wenn es ihn nicht gibt.</summary>
    function Restore(const ASurface: IAtlasDesignSurface; AIndex: Integer; out AOutcome: TAtlasUndoOutcome): Boolean;
    /// <summary>Der aktuelle Stand wird neuer Ausgangsstand.</summary>
    procedure Reset(const ASurface: IAtlasDesignSurface);
    /// <summary>Anzahl der Formulare mit Verlauf.</summary>
    function FormCount: Integer;
    /// <summary>Aus: Verläufe weg, nichts wird erfasst.</summary>
    property Enabled: Boolean read FEnabled write SetEnabled;
    /// <summary>Höchstzahl der Schritte je Formular (designer.undoSteps).</summary>
    property MaxSteps: Integer read FMaxSteps write FMaxSteps;
    /// <summary>Ein Erfassen ist einzureihen: nach dem laufenden Ereignis Capture rufen.</summary>
    property OnQueue: TProc read FOnQueue write FOnQueue;
  end;

implementation

const
  cDefaultSteps = 50;

{ TAtlasDesignerUndoFlow }

constructor TAtlasDesignerUndoFlow.Create(const AWords: TAtlasUndoWords; const AReasons: TAtlasUndoReasons);
begin
  inherited Create;
  FHistories := TObjectDictionary<TComponent, TAtlasFormUndoHistory>.Create([doOwnsValues]);
  FWords := AWords;
  FReasons := AReasons;
  FEnabled := True;
  FMaxSteps := cDefaultSteps;
end;

destructor TAtlasDesignerUndoFlow.Destroy;
begin
  FPending := nil;
  FOnQueue := nil;
  FHistories.Free;
  inherited Destroy;
end;

procedure TAtlasDesignerUndoFlow.SetEnabled(AValue: Boolean);
begin
  FEnabled := AValue;
  if not AValue then
  begin
    FHistories.Clear;
    FPending := nil;
  end;
end;

procedure TAtlasDesignerUndoFlow.ItemsChanged(const ASurface: IAtlasDesignSurface);
begin
  Queue(ASurface);
end;

procedure TAtlasDesignerUndoFlow.SelectionChanged(const ASurface: IAtlasDesignSurface);
begin
  // Vor der ersten Änderung den Ausgangsstand kennen.
  if (ASurface <> nil) and (ASurface.Root <> nil) and not FHistories.ContainsKey(ASurface.Root) then
  begin
    Queue(ASurface);
  end;
end;

procedure TAtlasDesignerUndoFlow.Opened(const ASurface: IAtlasDesignSurface);
begin
  Queue(ASurface);
end;

procedure TAtlasDesignerUndoFlow.Closed(const ASurface: IAtlasDesignSurface);
begin
  if (ASurface = nil) or (ASurface.Root = nil) then
  begin
    Exit;
  end;
  if (FPending <> nil) and (FPending.Root = ASurface.Root) then
  begin
    FPending := nil;
  end;
  FHistories.Remove(ASurface.Root);
end;

procedure TAtlasDesignerUndoFlow.Queue(const ASurface: IAtlasDesignSurface);
begin
  if FBusy or (ASurface = nil) or not FEnabled then
  begin
    Exit;
  end;
  FPending := ASurface;
  if FQueued then
  begin
    Exit;
  end;
  FQueued := True;
  if Assigned(FOnQueue) then
  begin
    FOnQueue();
  end;
end;

procedure TAtlasDesignerUndoFlow.Capture;
var
  mSurface: IAtlasDesignSurface;
  mRoot: TComponent;
  mHistory: TAtlasFormUndoHistory;
  mText: string;
begin
  FQueued := False;
  mSurface := FPending;
  FPending := nil;
  if (mSurface = nil) or FBusy or not FEnabled then
  begin
    Exit;
  end;
  mRoot := mSurface.Root;
  if mRoot = nil then
  begin
    Exit;
  end;
  mText := TAtlasDesignSurfaces.FormText(mSurface);
  mHistory := HistoryOf(mRoot);
  mHistory.MaxSteps := FMaxSteps;
  if mHistory.Count = 0 then
  begin
    mHistory.Add(mText, '');
  end
  else
  begin
    mHistory.Add(mText, TAtlasFormUndo.Describe(mHistory.State(mHistory.Index).Text, mText, FWords));
  end;
end;

function TAtlasDesignerUndoFlow.HistoryOf(ARoot: TComponent): TAtlasFormUndoHistory;
begin
  if not FHistories.TryGetValue(ARoot, Result) then
  begin
    Result := TAtlasFormUndoHistory.Create(FMaxSteps);
    FHistories.Add(ARoot, Result);
  end;
end;

function TAtlasDesignerUndoFlow.Active(const ASurface: IAtlasDesignSurface;
  out AHistory: TAtlasFormUndoHistory): Boolean;
var
  mHistory: TAtlasFormUndoHistory;
begin
  AHistory := nil;
  Result := FEnabled and (ASurface <> nil) and (ASurface.Root <> nil) and
    FHistories.TryGetValue(ASurface.Root, mHistory);
  if Result then
  begin
    AHistory := mHistory;
  end;
end;

function TAtlasDesignerUndoFlow.CanUndo(const ASurface: IAtlasDesignSurface): Boolean;
var
  mHistory: TAtlasFormUndoHistory;
begin
  Result := Active(ASurface, mHistory) and mHistory.CanUndo;
end;

function TAtlasDesignerUndoFlow.CanRedo(const ASurface: IAtlasDesignSurface): Boolean;
var
  mHistory: TAtlasFormUndoHistory;
begin
  Result := Active(ASurface, mHistory) and mHistory.CanRedo;
end;

function TAtlasDesignerUndoFlow.Restore(const ASurface: IAtlasDesignSurface; AIndex: Integer;
  out AOutcome: TAtlasUndoOutcome): Boolean;
var
  mHistory: TAtlasFormUndoHistory;
  mTarget: string;
  mApply: TAtlasDesignerUndoApply;
begin
  AOutcome := Default(TAtlasUndoOutcome);
  Result := Active(ASurface, mHistory) and (AIndex >= 0) and (AIndex < mHistory.Count);
  if not Result then
  begin
    Exit;
  end;
  mTarget := mHistory.State(AIndex).Text;
  mApply := TAtlasDesignerUndoApply.Create(ASurface, FReasons);
  FBusy := True;
  try
    try
      mApply.Run(TAtlasFormUndo.Plan(TAtlasDesignSurfaces.FormText(ASurface), mTarget), mTarget);
    finally
      ASurface.Modified;
      // Der tatsächliche Stand gilt; was nicht herstellbar war, bleibt so auch beim nächsten Schritt.
      mHistory.MoveTo(AIndex, TAtlasDesignSurfaces.FormText(ASurface));
      FBusy := False;
    end;
    AOutcome.Failures := mApply.Failures;
    AOutcome.MissingMethods := mApply.MissingMethods;
  finally
    mApply.Free;
  end;
end;

procedure TAtlasDesignerUndoFlow.Reset(const ASurface: IAtlasDesignSurface);
var
  mHistory: TAtlasFormUndoHistory;
begin
  if Active(ASurface, mHistory) then
  begin
    mHistory.Clear;
    mHistory.Add(TAtlasDesignSurfaces.FormText(ASurface), '');
  end;
end;

function TAtlasDesignerUndoFlow.FormCount: Integer;
begin
  Result := FHistories.Count;
end;

end.
