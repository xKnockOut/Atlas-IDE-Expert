unit Atlas.UI.Query.Frame.Tests;

// Fenster „Atlas-Abfrage“ (#1351), Fensterinhalt: Zeilen und Statuszeile aus
// der Antwort des Servers, Sortieren per Spaltenklick (Gleichstand eindeutig,
// ohne Wert zuletzt), Sprung zur Deklaration, Ausführen und Abbrechen,
// Fehler mit Spalte und Vorschlag, Vervollständigung aus Katalog und
// Symbolsuche, gespeicherte Abfragen, CSV.

interface

uses
  DUnitX.TestFramework,
  Vcl.Forms,
  Atlas.UI.Query.Frame;

type
  [TestFixture]
  TAtlasCodeQueryFrameTests = class
  private
    FForm: TForm;
    FFrame: TAtlasCodeQueryFrame;
    FOpened: string;
    FLine: Integer;
    FRan: string;
    FCancelled: Boolean;
  public
    /// <summary>Einmalige VCL-Puffer (Liste, Klappliste) vor dem Leckmonitor anlegen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Setup]
    procedure SetUp;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ShowsRowsAndStatus;
    [Test]
    procedure SortsByColumnClick;
    [Test]
    procedure OpensRowAndRuns;
    [Test]
    procedure ErrorShowsColumnAndSuggestion;
    [Test]
    procedure CompletesFromCatalogAndSymbols;
    [Test]
    procedure SavedQueryRuns;
    [Test]
    procedure CsvAndMessage;
  end;

implementation

uses
  System.Classes,
  System.SysUtils,
  Vcl.Controls,
  Atlas.UI.Strings,
  Atlas.Core.Query.Model,
  Atlas.Core.Query.Model.Tests;

function Joined(const ALines: TArray<string>): string;
begin
  Result := string.Join(#10, ALines);
end;

function FirstCells(const ALines: TArray<string>): string;
var
  mLine: string;
begin
  Result := '';
  for mLine in ALines do
  begin
    if Result <> '' then
      Result := Result + ',';
    Result := Result + mLine.Split([' | '])[0];
  end;
end;

procedure TAtlasCodeQueryFrameTests.WarmUpFirstUse;
begin
  SetUp;
  try
    ShowsRowsAndStatus;
  finally
    TearDown;
  end;
end;

procedure TAtlasCodeQueryFrameTests.SetUp;
var
  mAnswer: TAtlasQueryAnswer;
  mCatalog: TAtlasQueryCatalog;
begin
  FForm := TForm.CreateNew(nil);
  FForm.Width := 900;
  FForm.Height := 600;
  FFrame := TAtlasCodeQueryFrame.Create(FForm);
  FFrame.Parent := FForm;
  FFrame.Align := alClient;
  FFrame.OnOpenLocation :=
    procedure(AFileName: string; ALine, ACharacter: Integer)
    begin
      FOpened := AFileName;
      FLine := ALine;
    end;
  FFrame.OnRun :=
    procedure(AQuery: string)
    begin
      FRan := AQuery;
    end;
  FFrame.OnCancel :=
    procedure
    begin
      FCancelled := True;
    end;
  TAtlasQueryCatalog.Parse(QuerySampleCatalog, mCatalog);
  FFrame.SetCatalog(mCatalog);
  TAtlasQueryAnswer.Parse(QuerySampleAnswer, mAnswer);
  FFrame.SetAnswer(mAnswer);
end;

procedure TAtlasCodeQueryFrameTests.TearDown;
begin
  FForm.Free;
  FForm := nil;
  FFrame := nil;
  FOpened := '';
  FRan := '';
  FCancelled := False;
end;

procedure TAtlasCodeQueryFrameTests.ShowsRowsAndStatus;
var
  mRows: TArray<string>;
begin
  mRows := FFrame.RowText;
  Assert.AreEqual(3, Integer(Length(mRows)));
  Assert.AreEqual('TB | U | 9 | 2 | U.pas:9', mRows[0]);
  Assert.AreEqual('TA | U | 4 | 10 | U.pas:4 · ' + TAtlasStrings.Text(TAtlasTextId.QueryInferred), mRows[1]);
  // Spalten je Feld und „Datei“.
  Assert.AreEqual(5, FFrame.ResultList.Columns.Count);
  Assert.AreEqual(3, FFrame.ResultList.Items.Count);
  Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.QueryStatusTruncated, [3, 3, 12]) +
    TAtlasStrings.Fmt(TAtlasTextId.QueryStatusInferred, [1]), FFrame.StatusLabel.Caption);
  Assert.IsTrue(FFrame.CopyCsvButton.Enabled);
  Assert.IsFalse(FFrame.ErrorLabel.Visible);
end;

procedure TAtlasCodeQueryFrameTests.SortsByColumnClick;
begin
  // methods: Zahl, zuerst absteigend; ohne Wert zuletzt.
  FFrame.SortBy(3);
  Assert.AreEqual('TA,TB,TC;x', FirstCells(FFrame.RowText));
  Assert.IsTrue(FFrame.SortDescending);
  FFrame.SortBy(3);
  Assert.AreEqual('TB,TA,TC;x', FirstCells(FFrame.RowText));
  // unit: Gleichstand bei TA und TB, weiter nach Pfad und Zeile.
  FFrame.SortBy(1);
  Assert.IsFalse(FFrame.SortDescending);
  Assert.AreEqual('TA,TB,TC;x', FirstCells(FFrame.RowText));
  // „Datei“ sortiert nach Pfad, Zeile und Spalte.
  FFrame.SortBy(4);
  Assert.AreEqual(-1, FFrame.SortColumn);
  Assert.AreEqual('TA,TB,TC;x', FirstCells(FFrame.RowText));
end;

procedure TAtlasCodeQueryFrameTests.OpensRowAndRuns;
begin
  FFrame.OpenRow(0);
  Assert.AreEqual('C:\P\U.pas', FOpened);
  Assert.AreEqual(9, FLine);
  FFrame.Input.Text := '  classes where methods > 3  ';
  FFrame.Run;
  Assert.AreEqual('classes where methods > 3', FRan);
  FFrame.SetRunning(True);
  Assert.IsFalse(FFrame.RunButton.Enabled);
  Assert.IsTrue(FFrame.CancelButton.Enabled);
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.QueryRunning), FFrame.StatusLabel.Caption);
  // Während eine Abfrage läuft, startet keine zweite.
  FRan := '';
  FFrame.Run;
  Assert.AreEqual('', FRan);
  FFrame.CancelButton.Click;
  Assert.IsTrue(FCancelled);
  FFrame.SetMessage(TAtlasStrings.Text(TAtlasTextId.QueryCancelled), True);
  Assert.IsTrue(FFrame.RunButton.Enabled);
  Assert.IsFalse(FFrame.CancelButton.Enabled);
  // Die bisherigen Treffer bleiben stehen.
  Assert.AreEqual(3, Integer(Length(FFrame.RowText)));
end;

procedure TAtlasCodeQueryFrameTests.ErrorShowsColumnAndSuggestion;
var
  mAnswer: TAtlasQueryAnswer;
begin
  FFrame.Input.Text := 'classes where methds > 3';
  TAtlasQueryAnswer.Parse('{"enabled": true, "data": {"query": "classes where methds > 3", ' +
    '"error": {"message": "Unbekanntes Feld „methds“", "column": 15, "suggestion": "methods"}}}', mAnswer);
  FFrame.SetAnswer(mAnswer);
  Assert.IsTrue(FFrame.ErrorLabel.Visible);
  Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.QueryError, [15, 'Unbekanntes Feld „methds“']) + ' ' +
    TAtlasStrings.Fmt(TAtlasTextId.QuerySuggestion, ['methods']), FFrame.ErrorLabel.Caption);
  // Schreibmarke an der Fehlerstelle (Spalte 15 = nach 14 Zeichen).
  Assert.AreEqual(14, FFrame.Input.SelStart);
  Assert.AreEqual(0, Integer(Length(FFrame.RowText)));
  Assert.AreEqual('', FFrame.StatusLabel.Caption);
end;

procedure TAtlasCodeQueryFrameTests.CompletesFromCatalogAndSymbols;
var
  mPredicate: string;
begin
  FFrame.Input.Text := 'cl';
  FFrame.Input.SelStart := 2;
  FFrame.ShowSuggestions;
  Assert.AreEqual('classes', Joined(FFrame.Suggestions));
  Assert.IsTrue(FFrame.SuggestList.Visible);
  FFrame.AcceptSuggestion(0);
  Assert.AreEqual('classes ', FFrame.Input.Text);
  Assert.AreEqual(8, FFrame.Input.SelStart);
  Assert.IsFalse(FFrame.SuggestList.Visible);
  FFrame.OnSymbols :=
    function(const APredicate, APrefix: string): TArray<string>
    begin
      mPredicate := APredicate;
      Result := TArray<string>.Create(APrefix + 'ormBasis', APrefix + 'ormBasis', 'TFrameX');
    end;
  FFrame.Input.Text := 'classes where inherits TF and methods > 3';
  FFrame.Input.SelStart := 25;
  FFrame.ShowSuggestions;
  Assert.AreEqual('inherits', mPredicate);
  // Doppelte Namen nur einmal.
  Assert.AreEqual('TFormBasis'#10'TFrameX', Joined(FFrame.Suggestions));
  FFrame.AcceptSuggestion(0);
  Assert.AreEqual('classes where inherits TFormBasis  and methods > 3', FFrame.Input.Text);
  // Ein Zeichen reicht nicht für die Symbolsuche.
  mPredicate := '';
  FFrame.Input.Text := 'classes where inherits T';
  FFrame.Input.SelStart := 24;
  FFrame.ShowSuggestions;
  Assert.AreEqual('', mPredicate);
  Assert.IsFalse(FFrame.SuggestList.Visible);
end;

procedure TAtlasCodeQueryFrameTests.SavedQueryRuns;
begin
  // Hinweis vorn, dann die gespeicherten Abfragen.
  Assert.AreEqual(2, FFrame.SavedCombo.Items.Count);
  Assert.IsTrue(FFrame.SavedCombo.Enabled);
  FFrame.SavedCombo.ItemIndex := 1;
  FFrame.SavedCombo.OnChange(FFrame.SavedCombo);
  Assert.AreEqual('classes where methods > 40', FFrame.Input.Text);
  Assert.AreEqual('classes where methods > 40', FRan);
end;

procedure TAtlasCodeQueryFrameTests.CsvAndMessage;
begin
  Assert.IsTrue(FFrame.CsvText.StartsWith('name;unit;line;methods;path;inferred'), FFrame.CsvText);
  FFrame.SetMessage(TAtlasStrings.Text(TAtlasTextId.QueryNoServer), False);
  Assert.IsFalse(FFrame.HasAnswer);
  Assert.AreEqual(0, Integer(Length(FFrame.RowText)));
  Assert.AreEqual(0, FFrame.ResultList.Items.Count);
  Assert.IsFalse(FFrame.CopyCsvButton.Enabled);
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.QueryNoServer), FFrame.StatusLabel.Caption);
  Assert.AreEqual('', FFrame.CsvText);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasCodeQueryFrameTests);

end.
