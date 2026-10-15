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
  Atlas.UI.Diagnostics.TimingFrame;

function Queries: TArray<TAtlasQueryTiming>;
var
  Timings: TAtlasQueryTimings;
  Id: Integer;
begin
  Timings := TAtlasQueryTimings.Create;
  try
    Id := Timings.BeginQuery(0, 'Member, automatisch', 'Unit1.pas');
    Timings.ProviderDone(Id, 'Server', 500, 40);
    Timings.ProviderDone(Id, 'Code-Vorlagen', 1, 2);
    Timings.FilterSorted(2, 42, 7);
    Timings.Drawn(3);
    Result := Timings.Snapshot;
  finally
    Timings.Free;
  end;
end;

{ TAtlasTimingFrameTests }

procedure TAtlasTimingFrameTests.WarmUpFirstUse;
begin
  RowsWithProviderNamesAndWarnings;
end;

procedure TAtlasTimingFrameTests.EmptyShowsHint;
var
  Frame: TAtlasTimingFrame;
begin
  Frame := TAtlasTimingFrame.Create(nil);
  try
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.DiagnosticNoQuery), Frame.Title.Caption);
    Assert.AreEqual(5, Integer(Length(Frame.Rows)), 'Schritte ohne Quellen');
    Assert.IsFalse(Frame.FileNames.Checked, 'Dateinamen nur auf Wunsch');
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.DiagnosticCopy), Frame.CopyButton.Caption);
  finally
    Frame.Free;
  end;
end;

procedure TAtlasTimingFrameTests.RowsWithProviderNamesAndWarnings;
var
  Form: TForm;
  Frame: TAtlasTimingFrame;
  Row: TAtlasTimingRow;
  Seen: Boolean;
begin
  Form := TForm.CreateNew(nil);
  try
    Form.Width := 600;
    Form.Height := 400;
    Frame := TAtlasTimingFrame.Create(Form);
    Frame.Parent := Form;
    Frame.Align := alClient;
    Frame.SetColors(TAtlasColors.Dark);
    Frame.SetQueries(Queries);
    Assert.Contains(Frame.Title.Caption, 'Member, automatisch');
    Assert.AreEqual(7, Integer(Length(Frame.Rows)));
    Seen := False;
    for Row in Frame.Rows do
      if (Row.Kind = TAtlasTimingRowKind.Provider) and (Row.Name = 'Server') then
      begin
        Seen := True;
        Assert.IsTrue(Row.LastWarn, 'verzögerte Quelle in Warnfarbe');
        Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.DiagnosticRowProvider, ['Server']),
          TAtlasTimingFrame.Caption(Row));
      end;
    Assert.IsTrue(Seen);
    // Zeichnen mit Warnfläche darf nicht scheitern.
    Form.Show;
    Frame.Grid.Repaint;
    Application.ProcessMessages;
  finally
    Form.Free;
  end;
end;

procedure TAtlasTimingFrameTests.CopyPassesFileNameChoice;
var
  Frame: TAtlasTimingFrame;
  Calls: Integer;
  WithNames: Boolean;
begin
  Calls := 0;
  WithNames := True;
  Frame := TAtlasTimingFrame.Create(nil);
  try
    Frame.OnCopy :=
      procedure(AFileNames: Boolean)
      begin
        Inc(Calls);
        WithNames := AFileNames;
      end;
    Frame.CopyButton.Click;
    Assert.AreEqual(1, Calls);
    Assert.IsFalse(WithNames, 'Vorgabe ohne Dateinamen');
    Frame.FileNames.Checked := True;
    Frame.CopyButton.Click;
    Assert.IsTrue(WithNames);
    Frame.ShowNote(TAtlasStrings.Text(TAtlasTextId.DiagnosticCopied));
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.DiagnosticCopied), Frame.Note.Caption);
  finally
    Frame.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTimingFrameTests);

end.
