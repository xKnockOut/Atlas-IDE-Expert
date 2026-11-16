unit Atlas.Core.Designer.UndoFlow.Vcl.Tests;

// Ablauf von „Rückgängig im Designer“ (#1887) gegen die Fälschung des
// Designers mit echten VCL-Steuerelementen (Panel mit Knopf) auf einem nie
// gezeigten Formular: Verschieben wird als Schritt beschrieben, ein
// gelöschtes Panel kommt samt Kind und Lage zurück. Nur unter Delphi; die
// Abläufe ohne VCL stehen in Atlas.Core.Designer.UndoFlow.Tests.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Designer.Surface,
  Atlas.Core.Designer.UndoFlow,
  Atlas.Tests.DesignSurfaceFake;

type
  /// <summary>Dieselbe Fälschung mit VCL-Steuerelementen auf einem nie gezeigten Formular.</summary>
  [TestFixture]
  [Category('Atlas.IDE.Designer')]
  TAtlasDesignerUndoFlowVclTests = class
  private
    FFake: TAtlasDesignSurfaceFake;
    FSurface: IAtlasDesignSurface;
    FFlow: TAtlasDesignerUndoFlow;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure MovedButtonAndDeletedPanelComeBack;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.Forms,
  Atlas.Core.Designer.Undo,
  Atlas.Core.Designer.UndoApply,
  Atlas.Core.Designer.UndoFlow.Tests;

{ TAtlasDesignerUndoFlowVclTests }

procedure TAtlasDesignerUndoFlowVclTests.Setup;
var
  mForm: TForm;
begin
  mForm := TForm.CreateNew(nil);
  mForm.Name := 'Form1';
  FFake := TAtlasDesignSurfaceFake.Create(mForm);
  FSurface := FFake;
  FFlow := TAtlasDesignerUndoFlow.Create(UndoTestWords, UndoTestReasons);
  FFake.Listen(FFlow);
end;

procedure TAtlasDesignerUndoFlowVclTests.TearDown;
begin
  FFake.Unlisten(FFlow);
  FreeAndNil(FFlow);
  FFake := nil;
  FSurface := nil;
end;

procedure TAtlasDesignerUndoFlowVclTests.MovedButtonAndDeletedPanelComeBack;
var
  mPanel: TComponent;
  mButton: TButton;
  mHistory: TAtlasFormUndoHistory;
  mOutcome: TAtlasUndoOutcome;
begin
  mPanel := FFake.Insert(TPanel, nil, 'Panel1');
  mButton := TButton(FFake.Insert(TButton, mPanel, 'Button1'));
  mButton.SetBounds(8, 8, 75, 25);
  FFake.Open;
  FFlow.Capture;
  FFake.Change(
    procedure
    begin
      mButton.Left := 40;
    end);
  FFlow.Capture;
  Assert.IsTrue(FFlow.Active(FSurface, mHistory));
  Assert.AreEqual('Button1 moved (8, 8) -> (40, 8)', mHistory.State(1).Caption);
  // Das Panel samt Knopf löschen und zurückholen.
  FFake.Delete(mPanel);
  FFlow.Capture;
  Assert.IsNull(FSurface.Root.FindComponent('Button1'));
  Assert.IsTrue(FFlow.Restore(FSurface, 1, mOutcome));
  Assert.AreEqual(0, Integer(Length(mOutcome.Failures)), string.Join('; ', mOutcome.Failures));
  mPanel := FSurface.Root.FindComponent('Panel1');
  mButton := TButton(FSurface.Root.FindComponent('Button1'));
  Assert.IsNotNull(mPanel);
  Assert.IsNotNull(mButton);
  Assert.AreSame(mPanel, mButton.Parent);
  Assert.AreEqual(40, mButton.Left);
  Assert.IsTrue(FFlow.Restore(FSurface, 0, mOutcome));
  Assert.AreEqual(8, mButton.Left);
end;

initialization
  RegisterClasses([TPanel, TButton]);
  TDUnitX.RegisterTestFixture(TAtlasDesignerUndoFlowVclTests);

end.
