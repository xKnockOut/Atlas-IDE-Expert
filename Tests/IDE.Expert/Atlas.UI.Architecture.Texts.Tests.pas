unit Atlas.UI.Architecture.Texts.Tests;

// Texte der Architekturansicht ohne Steuerelemente: Unit-Namen, Fundstellen, Abhängigkeiten, Kanten und
// Änderungen des Vergleichs.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Analysis')]
  TAtlasArchitectureTextsTests = class
  public
    /// <summary>Name nach Index; außerhalb der Units leer.</summary>
    [Test]
    procedure UnitCaptionByIndex;
    /// <summary>Fundstelle „Datei:Zeile“ nur mit Datei und Zeile.</summary>
    [Test]
    procedure LocationNeedsFileAndLine;
    /// <summary>Abhängigkeit mit Abschnitt und Fundstelle.</summary>
    [Test]
    procedure LinkCaptionShowsSectionAndLocation;
    /// <summary>Kante im Vergleich: von → nach, Abschnitt; Wechsel mit Teilsystemen in Klammern.</summary>
    [Test]
    procedure ChangeTexts;
    /// <summary>Ohne Ausschlüsse, Angleichung und Vergleich kein Zusatz in der Statuszeile.</summary>
    [Test]
    procedure StatusNotesEmptyForPlainModel;
  end;

implementation

uses
  Atlas.Core.Architecture.Model,
  Atlas.UI.Architecture.Texts;

/// <summary>Modell mit den Units App.Main und App.Data.</summary>
function TwoUnits: TAtlasArchitectureModel;
begin
  Result := Default(TAtlasArchitectureModel);
  SetLength(Result.Units, 2);
  Result.Units[0].Name := 'App.Main';
  Result.Units[1].Name := 'App.Data';
end;

function Link(AInterface: Boolean; const AFileName: string; ALine: Integer): TAtlasArchLink;
begin
  Result := Default(TAtlasArchLink);
  Result.Source := 0;
  Result.Target := 1;
  Result.Interface_ := AInterface;
  Result.FileName := AFileName;
  Result.Line := ALine;
end;

procedure TAtlasArchitectureTextsTests.UnitCaptionByIndex;
var
  mModel: TAtlasArchitectureModel;
begin
  mModel := TwoUnits;
  Assert.AreEqual('App.Data', TAtlasArchitectureTexts.UnitCaption(mModel, 1));
  Assert.AreEqual('', TAtlasArchitectureTexts.UnitCaption(mModel, 2));
  Assert.AreEqual('', TAtlasArchitectureTexts.UnitCaption(mModel, -1));
end;

procedure TAtlasArchitectureTextsTests.LocationNeedsFileAndLine;
begin
  Assert.AreEqual('Src/Main.pas:12', TAtlasArchitectureTexts.LocationCaption(Link(True, 'Src/Main.pas', 12)));
  Assert.AreEqual('', TAtlasArchitectureTexts.LocationCaption(Link(True, 'Src/Main.pas', 0)));
  Assert.AreEqual('', TAtlasArchitectureTexts.LocationCaption(Link(True, '', 12)));
end;

procedure TAtlasArchitectureTextsTests.LinkCaptionShowsSectionAndLocation;
var
  mModel: TAtlasArchitectureModel;
begin
  mModel := TwoUnits;
  Assert.AreEqual('App.Main → App.Data (interface, Src/Main.pas:12)',
    TAtlasArchitectureTexts.LinkCaption(mModel, Link(True, 'Src/Main.pas', 12)));
  Assert.AreEqual('App.Main → App.Data (implementation)',
    TAtlasArchitectureTexts.LinkCaption(mModel, Link(False, '', 0)));
end;

procedure TAtlasArchitectureTextsTests.ChangeTexts;
var
  mChange: TAtlasArchChange;
begin
  mChange := Default(TAtlasArchChange);
  mChange.Text := 'App.Data';
  mChange.From := 'App';
  mChange.To_ := 'Data';
  Assert.AreEqual('App → Data', TAtlasArchitectureTexts.EdgeDetail(mChange));
  Assert.AreEqual('App.Data (App → Data)', TAtlasArchitectureTexts.ChangeCaption(TAtlasArchChangeKind.Moves,
    mChange));
  mChange.Section := 'interface';
  Assert.AreEqual('App → Data, interface', TAtlasArchitectureTexts.EdgeDetail(mChange));
  Assert.AreEqual('App.Data', TAtlasArchitectureTexts.ChangeCaption(TAtlasArchChangeKind.NewUnits, mChange));
end;

procedure TAtlasArchitectureTextsTests.StatusNotesEmptyForPlainModel;
begin
  Assert.AreEqual('', TAtlasArchitectureTexts.StatusNotes(TwoUnits));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasArchitectureTextsTests);

end.
