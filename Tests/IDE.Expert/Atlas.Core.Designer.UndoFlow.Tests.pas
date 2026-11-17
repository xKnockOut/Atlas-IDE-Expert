unit Atlas.Core.Designer.UndoFlow.Tests;

// Tests für den Ablauf von „Rückgängig im Designer“ (#1887) gegen die
// Fälschung des Designers (TAtlasDesignSurfaceFake): Erfassen nach dem
// Ereignis, Verlauf je Formular, Zurückladen mit Löschen, Anlegen, Werten
// und Handlern, Komponente während eines Schritts gelöscht, Formular
// geschlossen, mehrere Werkzeuge nacheinander. Mit einem TDataModule als
// Formular, damit die Tests auch unter FPC laufen; dieselben Abläufe mit
// VCL-Steuerelementen stehen in Atlas.Core.Designer.UndoFlow.Vcl.Tests.

interface

uses
  System.Classes,
  DUnitX.TestFramework,
  Atlas.Core.Designer.Undo,
  Atlas.Core.Designer.UndoApply,
  Atlas.Core.Designer.Surface,
  Atlas.Core.Designer.UndoFlow,
  Atlas.Tests.DesignSurfaceFake;

/// <summary>Texte der Schritte für Tests, auch die von Atlas.Core.Designer.Undo: englisch und ohne Pfeil, weil FPC
/// Strings mit Zeichen außerhalb von ASCII aus der Quelle anders vergleicht als Delphi.</summary>
function UndoTestWords: TAtlasUndoWords;
/// <summary>Gründe beim Zurückladen für Tests.</summary>
function UndoTestReasons: TAtlasUndoReasons;

type
  /// <summary>Komponente mit Werten, Liste und Ereignis, ohne VCL.</summary>
  TAtlasUndoWidget = class(TComponent)
  private
    FCaption: string;
    FSize: Integer;
    FLines: TStrings;
    FOnPing: TNotifyEvent;
    procedure SetLines(AValue: TStrings);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  published
    property Caption: string read FCaption write FCaption;
    property Size: Integer read FSize write FSize default 0;
    property Lines: TStrings read FLines write SetLines;
    property OnPing: TNotifyEvent read FOnPing write FOnPing;
  end;

  /// <summary>Zweites Werkzeug, das nur mitzählt.</summary>
  TAtlasUndoCountingTool = class(TAtlasDesignSurfaceListener)
  private
    FChanges: Integer;
  public
    procedure ItemsChanged(const ASurface: IAtlasDesignSurface); override;
    property Changes: Integer read FChanges;
  end;

  [TestFixture]
  [Category('Atlas.IDE.Designer')]
  TAtlasDesignerUndoFlowTests = class
  private
    FFake: TAtlasDesignSurfaceFake;
    FSurface: IAtlasDesignSurface;
    FFlow: TAtlasDesignerUndoFlow;
    FQueued: Integer;
    function Widget(const AName: string): TAtlasUndoWidget;
    /// <summary>Wie die IDE nach dem laufenden Ereignis.</summary>
    procedure AfterEvent;
    /// <summary>Formular mit Widget1 (Caption „Eins“, zwei Zeilen); Ausgangsstand erfasst.</summary>
    procedure OpenWithWidget;
    procedure SetCaption(const AName, ACaption: string);
    function Undo: TAtlasUndoOutcome;
    function Redo: TAtlasUndoOutcome;
    /// <summary>Zurück auf den Ausgangsstand, für WillRaise.</summary>
    procedure RestoreFirst;
  public
    /// <summary>Einmal-Belegungen (erstes Formular mit Verlauf, erstes Find/AreSame) vorwegnehmen; sie gehören
    /// nicht in die Leckmessung.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure OpenCapturesInitialState;
    [Test]
    procedure EventsBeforeCaptureMakeOneStep;
    [Test]
    procedure SelectionCapturesOnlyBeforeFirstChange;
    [Test]
    procedure UndoAndRedoRestoreValues;
    [Test]
    procedure UndoRecreatesDeletedComponent;
    [Test]
    procedure UndoDeletesInsertedComponent;
    [Test]
    procedure ComponentDeletedDuringStep;
    [Test]
    procedure ClosingDropsHistoryAndPendingCapture;
    [Test]
    procedure RestoreDoesNotCaptureOwnChanges;
    [Test]
    procedure FailedCleanupKeepsCapturing;
    [Test]
    procedure UndoRestoresHandler;
    [Test]
    procedure MissingHandlerIsReported;
    [Test]
    procedure RefusedDeleteIsReported;
    [Test]
    procedure ToolsChangeInTurn;
    [Test]
    procedure ResetMakesCurrentStateInitial;
    [Test]
    procedure DisabledClearsAndIgnores;
    [Test]
    procedure FindFollowsFrameKeys;
  end;


implementation

uses
  System.SysUtils;

function UndoTestWords: TAtlasUndoWords;
begin
  Result.Moved := '%s moved (%s, %s) -> (%s, %s)';
  Result.Resized := '%s size (%s, %s) -> (%s, %s)';
  Result.Changed := '%s.%s: %s -> %s';
  Result.ChangedMany := '%s: %d properties changed';
  Result.Inserted := '%s inserted';
  Result.Deleted := '%s deleted';
  Result.Renamed := '%s renamed to %s';
  Result.MovedMany := '%d components moved';
  Result.Several := '%d changes';
  Result.DefaultValue := '(default)';
end;

function UndoTestReasons: TAtlasUndoReasons;
begin
  Result.Delete := 'cannot delete';
  Result.Missing := 'missing';
  Result.ClassUnknown := 'class %s';
  Result.Value := 'value %s';
  Result.Skipped := 'inherited';
end;

{ TAtlasUndoWidget }

constructor TAtlasUndoWidget.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FLines := TStringList.Create;
end;

destructor TAtlasUndoWidget.Destroy;
begin
  FLines.Free;
  inherited Destroy;
end;

procedure TAtlasUndoWidget.SetLines(AValue: TStrings);
begin
  FLines.Assign(AValue);
end;

{ TAtlasUndoCountingTool }

procedure TAtlasUndoCountingTool.ItemsChanged(const ASurface: IAtlasDesignSurface);
begin
  Inc(FChanges);
end;

{ TAtlasDesignerUndoFlowTests }

procedure TAtlasDesignerUndoFlowTests.WarmUpFirstUse;
begin
  // Der erste Test der Fixture leckt (einzeln jeder), FindFollowsFrameKeys auch in der Fixture als einziger
  // mit Find/AreSame/IsNull: beide einmal ungemessen vorweg.
  Setup;
  try
    OpenCapturesInitialState;
  finally
    TearDown;
  end;
  Setup;
  try
    FindFollowsFrameKeys;
  finally
    TearDown;
  end;
end;

procedure TAtlasDesignerUndoFlowTests.Setup;
var
  mRoot: TDataModule;
begin
  mRoot := TDataModule.CreateNew(nil);
  mRoot.Name := 'Form1';
  FFake := TAtlasDesignSurfaceFake.Create(mRoot);
  FSurface := FFake;
  FFlow := TAtlasDesignerUndoFlow.Create(UndoTestWords, UndoTestReasons);
  FFlow.OnQueue :=
    procedure
    begin
      Inc(FQueued);
    end;
  FFake.Listen(FFlow);
  FQueued := 0;
end;

procedure TAtlasDesignerUndoFlowTests.TearDown;
begin
  if FFake <> nil then
  begin
    FFake.Unlisten(FFlow);
  end;
  FreeAndNil(FFlow);
  FFake := nil;
  FSurface := nil;
end;

function TAtlasDesignerUndoFlowTests.Widget(const AName: string): TAtlasUndoWidget;
begin
  Result := TAtlasUndoWidget(FSurface.Root.FindComponent(AName));
end;

procedure TAtlasDesignerUndoFlowTests.AfterEvent;
begin
  FFlow.Capture;
end;

procedure TAtlasDesignerUndoFlowTests.OpenWithWidget;
var
  mWidget: TAtlasUndoWidget;
begin
  mWidget := TAtlasUndoWidget(FFake.CreateComponent(TAtlasUndoWidget, nil));
  mWidget.Caption := 'Eins';
  mWidget.Lines.Text := 'a' + sLineBreak + 'b';
  FFake.Open;
  AfterEvent;
end;

procedure TAtlasDesignerUndoFlowTests.SetCaption(const AName, ACaption: string);
var
  mWidget: TAtlasUndoWidget;
begin
  mWidget := Widget(AName);
  FFake.Change(
    procedure
    begin
      mWidget.Caption := ACaption;
    end);
end;

function TAtlasDesignerUndoFlowTests.Undo: TAtlasUndoOutcome;
var
  mHistory: TAtlasFormUndoHistory;
begin
  Assert.IsTrue(FFlow.Active(FSurface, mHistory));
  Assert.IsTrue(FFlow.Restore(FSurface, mHistory.Index - 1, Result));
end;

function TAtlasDesignerUndoFlowTests.Redo: TAtlasUndoOutcome;
var
  mHistory: TAtlasFormUndoHistory;
begin
  Assert.IsTrue(FFlow.Active(FSurface, mHistory));
  Assert.IsTrue(FFlow.Restore(FSurface, mHistory.Index + 1, Result));
end;

procedure TAtlasDesignerUndoFlowTests.OpenCapturesInitialState;
var
  mHistory: TAtlasFormUndoHistory;
begin
  OpenWithWidget;
  Assert.IsTrue(FFlow.Active(FSurface, mHistory));
  Assert.AreEqual(1, mHistory.Count);
  Assert.AreEqual('', mHistory.State(0).Caption);
  Assert.IsFalse(FFlow.CanUndo(FSurface));
  Assert.IsFalse(FFlow.CanRedo(FSurface));
end;

procedure TAtlasDesignerUndoFlowTests.EventsBeforeCaptureMakeOneStep;
var
  mHistory: TAtlasFormUndoHistory;
begin
  OpenWithWidget;
  FQueued := 0;
  SetCaption('AtlasUndoWidget1', 'Zwei');
  SetCaption('AtlasUndoWidget1', 'Drei');
  Assert.AreEqual(1, FQueued, 'nur ein Erfassen eingereiht');
  AfterEvent;
  Assert.IsTrue(FFlow.Active(FSurface, mHistory));
  Assert.AreEqual(2, mHistory.Count);
  Assert.StartsWith('AtlasUndoWidget1.Caption: ', mHistory.State(1).Caption);
  Assert.EndsWith('Drei', mHistory.State(1).Caption.Replace('''', ''));
end;

procedure TAtlasDesignerUndoFlowTests.SelectionCapturesOnlyBeforeFirstChange;
begin
  FFake.CreateComponent(TAtlasUndoWidget, nil);
  FFake.Select;
  Assert.AreEqual(1, FQueued);
  AfterEvent;
  FFake.Select;
  Assert.AreEqual(1, FQueued, 'Ausgangsstand ist bekannt');
  Assert.AreEqual(1, FFlow.FormCount);
end;

procedure TAtlasDesignerUndoFlowTests.UndoAndRedoRestoreValues;
var
  mOutcome: TAtlasUndoOutcome;
begin
  OpenWithWidget;
  SetCaption('AtlasUndoWidget1', 'Zwei');
  AfterEvent;
  Assert.IsTrue(FFlow.CanUndo(FSurface));
  mOutcome := Undo;
  Assert.AreEqual('Eins', Widget('AtlasUndoWidget1').Caption);
  Assert.AreEqual(0, Integer(Length(mOutcome.Failures)));
  Assert.IsTrue(FFake.ModifiedCount > 0, 'Designer erfährt die Änderung');
  Assert.IsTrue(FFlow.CanRedo(FSurface));
  Redo;
  Assert.AreEqual('Zwei', Widget('AtlasUndoWidget1').Caption);
  Assert.IsFalse(FFlow.CanRedo(FSurface));
end;

procedure TAtlasDesignerUndoFlowTests.UndoRecreatesDeletedComponent;
var
  mOutcome: TAtlasUndoOutcome;
begin
  OpenWithWidget;
  FFake.Delete(Widget('AtlasUndoWidget1'));
  AfterEvent;
  Assert.IsNull(Widget('AtlasUndoWidget1'));
  mOutcome := Undo;
  Assert.IsNotNull(Widget('AtlasUndoWidget1'));
  Assert.AreEqual('Eins', Widget('AtlasUndoWidget1').Caption);
  Assert.AreEqual('a' + sLineBreak + 'b' + sLineBreak, Widget('AtlasUndoWidget1').Lines.Text);
  Assert.AreEqual(0, Integer(Length(mOutcome.Failures)));
end;

procedure TAtlasDesignerUndoFlowTests.UndoDeletesInsertedComponent;
var
  mHistory: TAtlasFormUndoHistory;
begin
  OpenWithWidget;
  FFake.Insert(TAtlasUndoWidget, nil, 'Neu');
  AfterEvent;
  Assert.IsTrue(FFlow.Active(FSurface, mHistory));
  Assert.AreEqual('Neu inserted', mHistory.State(1).Caption);
  Undo;
  Assert.IsNull(FSurface.Root.FindComponent('Neu'));
  Assert.IsNotNull(Widget('AtlasUndoWidget1'));
end;

procedure TAtlasDesignerUndoFlowTests.ComponentDeletedDuringStep;
var
  mHistory: TAtlasFormUndoHistory;
begin
  OpenWithWidget;
  // Erst geändert, dann noch im selben Ereignis gelöscht: Erfasst wird der Stand danach.
  SetCaption('AtlasUndoWidget1', 'Zwei');
  FFake.Delete(Widget('AtlasUndoWidget1'));
  AfterEvent;
  Assert.IsTrue(FFlow.Active(FSurface, mHistory));
  Assert.AreEqual(2, mHistory.Count);
  Assert.AreEqual('AtlasUndoWidget1 deleted', mHistory.State(1).Caption);
  Undo;
  Assert.AreEqual('Eins', Widget('AtlasUndoWidget1').Caption);
end;

procedure TAtlasDesignerUndoFlowTests.ClosingDropsHistoryAndPendingCapture;
begin
  OpenWithWidget;
  SetCaption('AtlasUndoWidget1', 'Zwei');
  FFake.Close;
  Assert.AreEqual(0, FFlow.FormCount);
  // Das eingereihte Erfassen kommt nach dem Schließen an.
  AfterEvent;
  Assert.AreEqual(0, FFlow.FormCount);
  Assert.IsFalse(FFlow.CanUndo(FSurface));
end;

procedure TAtlasDesignerUndoFlowTests.RestoreDoesNotCaptureOwnChanges;
var
  mHistory: TAtlasFormUndoHistory;
begin
  OpenWithWidget;
  FFake.Delete(Widget('AtlasUndoWidget1'));
  AfterEvent;
  FQueued := 0;
  // Anlegen meldet der Designer als Änderung; Atlas erfasst sie nicht als neuen Schritt.
  Undo;
  Assert.AreEqual(0, FQueued);
  Assert.IsTrue(FFlow.Active(FSurface, mHistory));
  Assert.AreEqual(2, mHistory.Count);
  Assert.AreEqual(0, mHistory.Index);
end;

procedure TAtlasDesignerUndoFlowTests.FailedCleanupKeepsCapturing;
var
  mHistory: TAtlasFormUndoHistory;
begin
  OpenWithWidget;
  SetCaption('AtlasUndoWidget1', 'Zwei');
  AfterEvent;
  FFake.FailModified := True;
  Assert.WillRaise(RestoreFirst, EAtlasDesignSurfaceFakeFailure);
  FFake.FailModified := False;
  // Der Verlauf steht trotzdem auf dem hergestellten Stand ...
  Assert.AreEqual('Eins', Widget('AtlasUndoWidget1').Caption);
  Assert.IsTrue(FFlow.Active(FSurface, mHistory));
  Assert.AreEqual(0, mHistory.Index);
  // ... und Rückgängig erfasst weiter Änderungen.
  FQueued := 0;
  SetCaption('AtlasUndoWidget1', 'Drei');
  Assert.AreEqual(1, FQueued, 'eingereiht');
  AfterEvent;
  Assert.AreEqual(1, mHistory.Index);
  Assert.IsTrue(FFlow.CanUndo(FSurface));
end;

procedure TAtlasDesignerUndoFlowTests.RestoreFirst;
var
  mOutcome: TAtlasUndoOutcome;
begin
  FFlow.Restore(FSurface, 0, mOutcome);
end;

procedure TAtlasDesignerUndoFlowTests.UndoRestoresHandler;
var
  mWidget: TAtlasUndoWidget;
  mHandler: TMethod;
begin
  mWidget := TAtlasUndoWidget(FFake.CreateComponent(TAtlasUndoWidget, nil));
  mHandler := FFake.Handler('WidgetPing');
  mWidget.OnPing := TNotifyEvent(mHandler);
  FFake.Open;
  AfterEvent;
  FFake.Change(
    procedure
    begin
      mWidget.OnPing := nil;
    end);
  AfterEvent;
  Undo;
  Assert.AreEqual('WidgetPing', FSurface.MethodName(TMethod(mWidget.OnPing)));
end;

procedure TAtlasDesignerUndoFlowTests.MissingHandlerIsReported;
var
  mWidget: TAtlasUndoWidget;
  mOutcome: TAtlasUndoOutcome;
begin
  mWidget := TAtlasUndoWidget(FFake.CreateComponent(TAtlasUndoWidget, nil));
  mWidget.OnPing := TNotifyEvent(FFake.Handler('WidgetPing'));
  FFake.Open;
  AfterEvent;
  FFake.Change(
    procedure
    begin
      mWidget.OnPing := nil;
    end);
  AfterEvent;
  FFake.RemoveMethod('WidgetPing');
  mOutcome := Undo;
  Assert.AreEqual(1, Integer(Length(mOutcome.MissingMethods)));
  Assert.AreEqual('WidgetPing', mOutcome.MissingMethods[0].Handler);
  Assert.AreEqual('OnPing', mOutcome.MissingMethods[0].Path);
  Assert.IsFalse(Assigned(mWidget.OnPing), 'kein neuer Handler im Code');
end;

procedure TAtlasDesignerUndoFlowTests.RefusedDeleteIsReported;
var
  mOutcome: TAtlasUndoOutcome;
begin
  OpenWithWidget;
  FFake.Insert(TAtlasUndoWidget, nil, 'Geerbt');
  AfterEvent;
  FFake.RefuseDelete('Geerbt');
  mOutcome := Undo;
  Assert.AreEqual(1, Integer(Length(mOutcome.Failures)));
  Assert.AreEqual('Geerbt (cannot delete)', mOutcome.Failures[0]);
  Assert.IsNotNull(FSurface.Root.FindComponent('Geerbt'));
  // Der erreichte Stand gilt: Geerbt steht auch im Stand 0, Wiederherstellen bleibt möglich.
  Assert.IsTrue(FFlow.CanRedo(FSurface));
  Assert.IsFalse(FFlow.CanUndo(FSurface));
end;

procedure TAtlasDesignerUndoFlowTests.ToolsChangeInTurn;
var
  mOther: TAtlasUndoCountingTool;
  mHistory: TAtlasFormUndoHistory;
  mWidget: TAtlasUndoWidget;
begin
  mOther := TAtlasUndoCountingTool.Create;
  try
    FFake.Listen(mOther);
    OpenWithWidget;
    mWidget := Widget('AtlasUndoWidget1');
    // Werkzeug A setzt die Größe, Werkzeug B die Beschriftung, je ein Schritt.
    FFake.Change(
      procedure
      begin
        mWidget.Size := 40;
      end);
    AfterEvent;
    SetCaption('AtlasUndoWidget1', 'Zwei');
    AfterEvent;
    Assert.IsTrue(FFlow.Active(FSurface, mHistory));
    Assert.AreEqual(3, mHistory.Count);
    Undo;
    Assert.AreEqual('Eins', mWidget.Caption);
    Assert.AreEqual(40, mWidget.Size);
    Undo;
    Assert.AreEqual(0, mWidget.Size);
    Assert.IsTrue(mOther.Changes >= 3, 'jedes Werkzeug hört alle Änderungen');
  finally
    FFake.Unlisten(mOther);
    mOther.Free;
  end;
end;

procedure TAtlasDesignerUndoFlowTests.ResetMakesCurrentStateInitial;
var
  mHistory: TAtlasFormUndoHistory;
begin
  OpenWithWidget;
  SetCaption('AtlasUndoWidget1', 'Zwei');
  AfterEvent;
  FFlow.Reset(FSurface);
  Assert.IsTrue(FFlow.Active(FSurface, mHistory));
  Assert.AreEqual(1, mHistory.Count);
  Assert.IsFalse(FFlow.CanUndo(FSurface));
end;

procedure TAtlasDesignerUndoFlowTests.DisabledClearsAndIgnores;
begin
  OpenWithWidget;
  FFlow.Enabled := False;
  Assert.AreEqual(0, FFlow.FormCount);
  FQueued := 0;
  SetCaption('AtlasUndoWidget1', 'Zwei');
  Assert.AreEqual(0, FQueued);
  AfterEvent;
  Assert.AreEqual(0, FFlow.FormCount);
end;

procedure TAtlasDesignerUndoFlowTests.FindFollowsFrameKeys;
var
  mFrame, mInner: TComponent;
begin
  mFrame := TComponent.Create(FSurface.Root);
  mFrame.Name := 'Frame1';
  mInner := TComponent.Create(mFrame);
  mInner.Name := 'Button1';
  Assert.AreSame(FSurface.Root, TAtlasDesignSurfaces.Find(FSurface.Root, ''));
  Assert.AreSame(mInner, TAtlasDesignSurfaces.Find(FSurface.Root, 'Frame1.Button1'));
  Assert.IsNull(TAtlasDesignSurfaces.Find(FSurface.Root, 'Frame1.Fehlt'));
  Assert.IsNull(TAtlasDesignSurfaces.Find(nil, 'Frame1'));
end;

initialization
  RegisterClass(TAtlasUndoWidget);
  TDUnitX.RegisterTestFixture(TAtlasDesignerUndoFlowTests);

end.
