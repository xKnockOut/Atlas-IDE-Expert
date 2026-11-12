unit Atlas.UI.Foundation.WrapLabel.Tests;

// Umbrechende Beschriftung: Die Höhe folgt der Breite in beide Richtungen,
// auch wenn die Breite erst nach dem Text kommt (alTop beim Aufbau).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasWrapLabelTests = class
  public
    [Test]
    procedure WiderMakesLower;
    [Test]
    procedure NarrowerMakesHigher;
    [Test]
    procedure AlignTopFollowsParentWidth;
    [Test]
    procedure WithoutAutoSizeKeepsHeight;
  end;

implementation

uses
  System.SysUtils,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.Forms,
  Atlas.UI.Foundation.WrapLabel;

const
  cWide = 1000;
  cNarrow = 80;
  cLongText = 'Board zeigt Spalten in falscher Reihenfolge nach dem Umbenennen einer Spalte in YouTrack';

/// <summary>Höhe einer Zeile in der Schrift von ALabel: ein Label ohne Umbruch misst sie.</summary>
function OneLine(ALabel: TAtlasWrapLabel): Integer;
var
  mProbe: TLabel;
begin
  mProbe := TLabel.Create(nil);
  try
    mProbe.Parent := ALabel.Parent;
    mProbe.Font := ALabel.Font;
    mProbe.Caption := 'Ag';
    Result := mProbe.Height;
  finally
    mProbe.Free;
  end;
end;

procedure TAtlasWrapLabelTests.WiderMakesLower;
var
  mForm: TForm;
  mLabel: TAtlasWrapLabel;
  mNarrow: Integer;
begin
  mForm := TForm.CreateNew(nil);
  try
    mLabel := TAtlasWrapLabel.Create(mForm);
    mLabel.Parent := mForm;
    mLabel.Caption := cLongText;
    mNarrow := mLabel.Height;
    Assert.IsTrue(mNarrow > 2 * OneLine(mLabel), 'bei 65 Pixeln mehrzeilig');
    mLabel.Width := mForm.ScaleValue(cWide);
    Assert.AreEqual(OneLine(mLabel), mLabel.Height);
  finally
    mForm.Free;
  end;
end;

procedure TAtlasWrapLabelTests.NarrowerMakesHigher;
var
  mForm: TForm;
  mLabel: TAtlasWrapLabel;
begin
  mForm := TForm.CreateNew(nil);
  try
    mLabel := TAtlasWrapLabel.Create(mForm);
    mLabel.Parent := mForm;
    mLabel.Width := mForm.ScaleValue(cWide);
    mLabel.Caption := cLongText;
    Assert.AreEqual(OneLine(mLabel), mLabel.Height);
    mLabel.Width := mForm.ScaleValue(cNarrow);
    Assert.IsTrue(mLabel.Height > 2 * OneLine(mLabel));
  finally
    mForm.Free;
  end;
end;

procedure TAtlasWrapLabelTests.AlignTopFollowsParentWidth;
var
  mForm: TForm;
  mLabel: TAtlasWrapLabel;
begin
  mForm := TForm.CreateNew(nil);
  try
    mForm.HandleNeeded;
    mForm.ClientWidth := mForm.ScaleValue(cWide);
    mForm.DisableAlign;
    try
      mLabel := TAtlasWrapLabel.Create(mForm);
      mLabel.Parent := mForm;
      mLabel.Align := alTop;
      mLabel.Caption := cLongText;
    finally
      mForm.EnableAlign;
    end;
    Assert.AreEqual(mForm.ClientWidth, mLabel.Width);
    Assert.AreEqual(OneLine(mLabel), mLabel.Height);
  finally
    mForm.Free;
  end;
end;

procedure TAtlasWrapLabelTests.WithoutAutoSizeKeepsHeight;
var
  mForm: TForm;
  mLabel: TAtlasWrapLabel;
begin
  mForm := TForm.CreateNew(nil);
  try
    mLabel := TAtlasWrapLabel.Create(mForm);
    mLabel.Parent := mForm;
    mLabel.AutoSize := False;
    mLabel.Caption := cLongText;
    mLabel.SetBounds(0, 0, 80, 40);
    mLabel.Width := mForm.ScaleValue(cWide);
    Assert.AreEqual(40, mLabel.Height);
  finally
    mForm.Free;
  end;
end;

end.
