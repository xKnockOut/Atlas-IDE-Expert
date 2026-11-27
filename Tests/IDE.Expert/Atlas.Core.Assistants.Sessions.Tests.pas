unit Atlas.Core.Assistants.Sessions.Tests;

// Assistenten dieser IDE-Sitzung (#2616): Nummern in der Reihenfolge des Auftretens, gleiche Sitzung gleiche Nummer,
// Farben je Sitzung, unbekannte Herkunft ohne Nummer.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Assistants')]
  TAtlasAssistantSessionsTests = class
  public
    [Test]
    procedure NumbersInOrderOfAppearance;
    [Test]
    procedure SameClientTwoSessionsAreTwoAssistants;
    [Test]
    procedure UnknownOriginHasNoNumber;
    [Test]
    procedure ColorsRepeatAfterThePalette;
    [Test]
    procedure KnownDoesNotAdd;
    [Test]
    procedure ColorsComeFromThePalette;
  end;

implementation

uses
  Atlas.Plugin.Style.Palette,
  Atlas.Text.AssistantOrigin,
  Atlas.Core.Assistants.Sessions;

{ TAtlasAssistantSessionsTests }

procedure TAtlasAssistantSessionsTests.NumbersInOrderOfAppearance;
var
  mSessions: TAtlasAssistantSessions;
begin
  mSessions := TAtlasAssistantSessions.Create;
  try
    Assert.AreEqual(0, mSessions.IndexOf(TAtlasAssistantOrigin.Make('Assistent A', '3f2a')));
    Assert.AreEqual(1, mSessions.IndexOf(TAtlasAssistantOrigin.Make('Assistent B', 'a91b')));
    Assert.AreEqual(0, mSessions.IndexOf(TAtlasAssistantOrigin.Make('Assistent A', '3f2a')));
    Assert.AreEqual(2, mSessions.Count);
    Assert.AreEqual('Assistent B', mSessions.Origins[1].Client);
  finally
    mSessions.Free;
  end;
end;

procedure TAtlasAssistantSessionsTests.SameClientTwoSessionsAreTwoAssistants;
var
  mSessions: TAtlasAssistantSessions;
begin
  mSessions := TAtlasAssistantSessions.Create;
  try
    Assert.AreEqual(0, mSessions.IndexOf(TAtlasAssistantOrigin.Make('Assistent A', '3f2a')));
    Assert.AreEqual(1, mSessions.IndexOf(TAtlasAssistantOrigin.Make('Assistent A', '77c0')));
    // Erst nur die Sitzung, später mit Name: derselbe Assistent, der Name wird nachgetragen.
    Assert.AreEqual(2, mSessions.IndexOf(TAtlasAssistantOrigin.Make('', 'b001')));
    Assert.AreEqual(2, mSessions.IndexOf(TAtlasAssistantOrigin.Make('Assistent C', 'b001')));
    Assert.AreEqual('Assistent C', mSessions.Origins[2].Client);
  finally
    mSessions.Free;
  end;
end;

procedure TAtlasAssistantSessionsTests.UnknownOriginHasNoNumber;
var
  mSessions: TAtlasAssistantSessions;
begin
  mSessions := TAtlasAssistantSessions.Create;
  try
    Assert.AreEqual(-1, mSessions.IndexOf(Default(TAtlasAssistantOrigin)));
    Assert.AreEqual(0, mSessions.Count);
    Assert.AreEqual(-1, TAtlasAssistantSessions.ColorIndex(-1, 6));
  finally
    mSessions.Free;
  end;
end;

procedure TAtlasAssistantSessionsTests.ColorsRepeatAfterThePalette;
begin
  Assert.AreEqual(0, TAtlasAssistantSessions.ColorIndex(0, 6));
  Assert.AreEqual(5, TAtlasAssistantSessions.ColorIndex(5, 6));
  Assert.AreEqual(0, TAtlasAssistantSessions.ColorIndex(6, 6));
  Assert.AreEqual(-1, TAtlasAssistantSessions.ColorIndex(3, 0));
end;

procedure TAtlasAssistantSessionsTests.KnownDoesNotAdd;
var
  mSessions: TAtlasAssistantSessions;
begin
  mSessions := TAtlasAssistantSessions.Create;
  try
    Assert.AreEqual(-1, mSessions.Known(TAtlasAssistantOrigin.Make('Assistent A', '3f2a')));
    Assert.AreEqual(0, mSessions.Count);
    mSessions.IndexOf(TAtlasAssistantOrigin.Make('Assistent A', '3f2a'));
    Assert.AreEqual(0, mSessions.Known(TAtlasAssistantOrigin.Make('Assistent A', '3f2a')));
  finally
    mSessions.Free;
  end;
end;

procedure TAtlasAssistantSessionsTests.ColorsComeFromThePalette;
var
  mColors: TAtlasColors;
begin
  mColors := TAtlasColors.Light;
  Assert.AreEqual(Cardinal(mColors.Muted), Cardinal(TAtlasAssistantSessions.ColorOf(-1, mColors)));
  Assert.AreEqual(Cardinal(mColors.Placeholders[0]), Cardinal(TAtlasAssistantSessions.ColorOf(0, mColors)));
  Assert.AreEqual(Cardinal(mColors.Placeholders[1]), Cardinal(TAtlasAssistantSessions.ColorOf(1, mColors)));
  Assert.AreNotEqual(Cardinal(TAtlasAssistantSessions.ColorOf(0, mColors)),
    Cardinal(TAtlasAssistantSessions.ColorOf(1, mColors)));
  Assert.AreEqual(Cardinal(mColors.Placeholders[0]),
    Cardinal(TAtlasAssistantSessions.ColorOf(Length(mColors.Placeholders), mColors)));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasAssistantSessionsTests);

end.
