unit Atlas.UI.Diagnostics.TimingFrame.Tests;

// Inhalt des Diagnosefensters (#479): Zeilen je Schritt und Quelle mit Namen,
// Titel der letzten Abfrage, Zeichnen ohne Fehler (auch mit Warnfarbe) und
// „Bericht kopieren“ mit der Wahl „Dateinamen in den Bericht“ (Vorgabe aus).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasTimingFrameTests = class
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Test]
    procedure EmptyShowsHint;
    [Test]
    procedure RowsWithProviderNamesAndWarnings;
    [Test]
    procedure CopyPassesFileNameChoice;
  end;

implementation

uses
  System.SysUtils,
  Vcl.Controls,
  Vcl.Forms,
  Atlas.Core.Style.Palette,
  Atlas.Core.Diagnostics.Timing,
  Atlas.UI.Strings,
  Atlas.UI.Diagnostics.Strings,
  Atlas.UI.Diagnostics.TimingFrame;

function Queries: TArray<TAtlasQueryTiming>;
var
  mTimings: TAtlasQueryTimings;
  mId: Integer;
begin
  mTimings := TAtlasQueryTimings.Create;
  try
    mId := mTimings.BeginQuery(0, 'Member, automatisch', 'Unit1.pas');
    mTimings.ProviderDone(mId, 'Server', 500, 40);
    mTimings.ProviderDone(mId, 'Code-Vorlagen', 1, 2);
    mTimings.FilterSorted(2, 42, 7);
    mTimings.Drawn(3);
    Result := mTimings.Snapshot;
  finally
    mTimings.Free;
  end;
end;

{ TAtlasTimingFrameTests }

procedure TAtlasTimingFrameTests.WarmUpFirstUse;
begin
  RowsWithProviderNamesAndWarnings;
end;

procedure TAtlasTimingFrameTests.EmptyShowsHint;
var
  mFrame: TAtlasTimingFrame;
begin
  mFrame := TAtlasTimingFrame.Create(nil);
  try
    Assert.AreEqual(TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.DiagnosticNoQuery), mFrame.Title.Caption);
    Assert.AreEqual(5, Integer(Length(mFrame.Rows)), 'Schritte ohne Quellen');
    Assert.IsFalse(mFrame.FileNames.Checked, 'Dateinamen nur auf Wunsch');
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.DiagnosticCopy), mFrame.CopyButton.Caption);
  finally
    mFrame.Free;
  end;
end;

procedure TAtlasTimingFrameTests.RowsWithProviderNamesAndWarnings;
var
  mForm: TForm;
  mFrame: TAtlasTimingFrame;
  mRow: TAtlasTimingRow;
  mSeen: Boolean;
begin
  mForm := TForm.CreateNew(nil);
  try
    mForm.Width := 600;
    mForm.Height := 400;
    mFrame := TAtlasTimingFrame.Create(mForm);
    mFrame.Parent := mForm;
    mFrame.Align := alClient;
    mFrame.SetColors(TAtlasColors.Dark);
    mFrame.SetQueries(Queries);
    Assert.Contains(mFrame.Title.Caption, 'Member, automatisch');
    Assert.AreEqual(7, Integer(Length(mFrame.Rows)));
    mSeen := False;
    for mRow in mFrame.Rows do
    begin
      if (mRow.Kind = TAtlasTimingRowKind.Provider) and (mRow.Name = 'Server') then
      begin
        mSeen := True;
        Assert.IsTrue(mRow.LastWarn, 'verzögerte Quelle in Warnfarbe');
        Assert.AreEqual(TAtlasDiagnosticsStrings.Fmt(TAtlasDiagnosticsTextId.DiagnosticRowProvider, ['Server']),
          TAtlasTimingFrame.Caption(mRow));
      end;
    end;
    Assert.IsTrue(mSeen);
    // Zeichnen mit Warnfläche darf nicht scheitern.
    mForm.Show;
    mFrame.Grid.Repaint;
    Application.ProcessMessages;
  finally
    mForm.Free;
  end;
end;

procedure TAtlasTimingFrameTests.CopyPassesFileNameChoice;
var
  mFrame: TAtlasTimingFrame;
  mCalls: Integer;
  mWithNames: Boolean;
begin
  mCalls := 0;
  mWithNames := True;
  mFrame := TAtlasTimingFrame.Create(nil);
  try
    mFrame.OnCopy :=
      procedure(AFileNames: Boolean)
      begin
        Inc(mCalls);
        mWithNames := AFileNames;
      end;
    mFrame.CopyButton.Click;
    Assert.AreEqual(1, mCalls);
    Assert.IsFalse(mWithNames, 'Vorgabe ohne Dateinamen');
    mFrame.FileNames.Checked := True;
    mFrame.CopyButton.Click;
    Assert.IsTrue(mWithNames);
    mFrame.ShowNote(TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.DiagnosticCopied));
    Assert.AreEqual(TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.DiagnosticCopied), mFrame.Note.Caption);
  finally
    mFrame.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTimingFrameTests);

end.
