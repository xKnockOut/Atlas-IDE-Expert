unit Atlas.UI.Debug.BreakpointAnchors.Tests;

// Dialog „Verwaiste Haltepunkte“ (#841): Text je Eintrag, Übernehmen und
// Löschen über die Aktion, Eintrag verschwindet nur bei Erfolg.

interface

uses
  DUnitX.TestFramework,
  Atlas.UI.Strings;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasBreakpointOrphanDialogTests = class
  private
    FLanguage: TAtlasLanguage;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ItemText;
    [Test]
    procedure ActRemovesOnSuccessOnly;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Editor.MethodAnchor,
  Atlas.Core.Debug.BreakpointAnchors,
  Atlas.UI.Debug.BreakpointAnchors;

function Orphan(ALine, ASuggestion: Integer): TAtlasAnchorOrphan;
var
  mAnchor: TAtlasMethodAnchor;
begin
  mAnchor := Default(TAtlasMethodAnchor);
  mAnchor.Anchor.Text := 'Schreibe;';
  Result := Default(TAtlasAnchorOrphan);
  Result.Item := TAtlasAnchoredBreakpoint.Create('C:\Src\Kunden.pas', ALine, mAnchor);
  Result.Suggestion := ASuggestion;
end;

{ TAtlasBreakpointOrphanDialogTests }

procedure TAtlasBreakpointOrphanDialogTests.Setup;
begin
  FLanguage := TAtlasStrings.Language;
  TAtlasStrings.Language := TAtlasLanguage.German;
end;

procedure TAtlasBreakpointOrphanDialogTests.TearDown;
begin
  TAtlasStrings.Language := FLanguage;
end;

procedure TAtlasBreakpointOrphanDialogTests.ItemText;
begin
  Assert.AreEqual('Kunden.pas:42  Schreibe;  (Vorschlag: Zeile 40)',
    TAtlasBreakpointOrphanDialog.ItemText(Orphan(41, 39)));
end;

procedure TAtlasBreakpointOrphanDialogTests.ActRemovesOnSuccessOnly;
var
  mDialog: TAtlasBreakpointOrphanDialog;
  mCalls: string;
  mSucceed: Boolean;
begin
  mCalls := '';
  mSucceed := False;
  mDialog := TAtlasBreakpointOrphanDialog.CreateDialog(nil, [Orphan(41, 39), Orphan(7, 5)],
    function(const AOrphan: TAtlasAnchorOrphan; ADelete: Boolean): Boolean
    begin
      mCalls := mCalls + Format('%d:%s;', [AOrphan.Item.Line, BoolToStr(ADelete, True)]);
      Result := mSucceed;
    end);
  try
    mDialog.HandleNeeded;
    mDialog.Fill;
    Assert.AreEqual(2, mDialog.OrphanList.Items.Count);
    mDialog.Act(False);
    Assert.AreEqual(2, mDialog.OrphanList.Items.Count, 'Fehlgeschlagen: Eintrag bleibt');
    mSucceed := True;
    mDialog.Act(True);
    Assert.AreEqual(1, mDialog.OrphanList.Items.Count);
    Assert.AreEqual(1, Integer(Length(mDialog.Orphans)));
    Assert.AreEqual(7, mDialog.Orphans[0].Item.Line);
    Assert.AreEqual('41:False;41:True;', mCalls);
  finally
    mDialog.Free;
  end;
  mCalls := '';
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasBreakpointOrphanDialogTests);

end.
