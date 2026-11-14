unit Atlas.Core.Hover.Layout.Members.Tests;

// Tests der published-Mitglieder im Hover-Satz (#110, #1841): Tabellen mit Schaltern, Rollbereich und
// Klickflächen außerhalb des Rollbereichs. Messwerte wie in Atlas.Core.Hover.Layout.TestSupport.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  THoverLayoutMembersTests = class
  public
    /// <summary>#110: published-Mitglieder als Tabellen mit Schaltern.</summary>
    [Test]
    procedure PublishedMembersAsTables;
    /// <summary>#1841: Tabellen der published-Mitglieder scrollen ab hover.membersMaxLines bzw. Bildschirmhöhe.
    /// </summary>
    [Test]
    procedure PublishedMembersScroll;
    /// <summary>#1841: Klickflächen außerhalb des sichtbaren Rollbereichs entfallen.</summary>
    [Test]
    procedure ScrolledMembersDropHiddenHits;
    /// <summary>Ohne Mitglieder und Standard-Property setzt der Maler nichts.</summary>
    [Test]
    procedure PainterWithoutMembersAddsNothing;
    /// <summary>Nur eine Standard-Property: Trennlinie und Zeile darunter, der Satz wächst nach unten.</summary>
    [Test]
    procedure PainterShowsDefaultPropertyOnly;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Style.Palette,
  Atlas.Core.Hover.Contract,
  Atlas.Core.Hover.Items,
  Atlas.Core.Hover.Layout,
  Atlas.Core.Hover.Layout.Contract,
  Atlas.Core.Hover.Layout.Members,
  Atlas.Core.Hover.View,
  Atlas.Core.Hover.Layout.TestSupport;

type
  /// <summary>Ruft den Maler der published-Mitglieder ohne den übrigen Satz auf.</summary>
  TMembersProbe = class(TAtlasHoverMembersPainter)
  public
    /// <summary>Malt ab Zeile 10 und liefert die neue Zeile.</summary>
    function Run: Integer;
    /// <summary>Ob ein Baustein genau AText zeigt.</summary>
    function Shows(const AText: string): Boolean;
    property ItemCount: Integer read FItemCount;
  end;

function TMembersProbe.Run: Integer;
begin
  FLeft := 8;
  FRight := FInput.Width - 8;
  FX := FLeft;
  FY := 10;
  PublishedMembers;
  Result := FY;
end;

function TMembersProbe.Shows(const AText: string): Boolean;
var
  mIndex: Integer;
begin
  for mIndex := 0 to FItemCount - 1 do
  begin
    if FItems[mIndex].Text = AText then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function Member(const AName, AType, ADeclaring: string; AKind: TAtlasHoverDefaultKind;
  const AValue: string): TAtlasHoverMember;
begin
  Result := Default(TAtlasHoverMember);
  Result.Name := AName;
  Result.TypeName := AType;
  Result.DeclaringClass := ADeclaring;
  Result.DefaultKind := AKind;
  Result.DefaultValue := AValue;
end;

function EventMember(const AName, AType, ADeclaring: string): TAtlasHoverMember;
begin
  Result := Member(AName, AType, ADeclaring, hdNone, '');
  Result.IsEvent := True;
end;

/// <summary>Kennungen der published-Treffer in ihrer Reihenfolge.</summary>
function PublishedCodes(const ALayout: TAtlasHoverLayout): string;
var
  mHit: TAtlasHoverHit;
begin
  Result := '';
  for mHit in ALayout.Hits do
  begin
    if mHit.Kind = TAtlasHoverHitKind.Published then
    begin
      Result := Result + IntToStr(mHit.Index);
    end;
  end;
end;

/// <summary>Ob ein Element des Layouts genau diesen Text zeigt.</summary>
function HasItemText(const ALayout: TAtlasHoverLayout; const AText: string): Boolean;
var
  mItem: TAtlasHoverItem;
begin
  for mItem in ALayout.Items do
  begin
    if mItem.Text = AText then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Schalter, Abschnitte, weitere Zeilen, geerbte und nur mit default.</summary>
procedure AssertPublishedToggles(const AHoverView: TAtlasHoverView; const AHoverInput: TAtlasHoverInput;
  const ALayout: TAtlasHoverLayout);
var
  mHoverView: TAtlasHoverView;
  mHoverInput: TAtlasHoverInput;
  mLayout: TAtlasHoverLayout;
begin
  mHoverView := AHoverView;
  mHoverInput := AHoverInput;
  mLayout := ALayout;
  // Schalter, Abschnitte, „+ 1 weitere Properties“ (8 > 7), „+ 1 weitere Ereignisse“ (5 > 4).
  Assert.AreEqual('012435', PublishedCodes(mLayout));
  Assert.IsTrue(HasItemText(mLayout, 'published: 8 Properties · 5 Ereignisse'));
  Assert.IsTrue(HasItemText(mLayout, 'PROPERTIES ▾'));
  Assert.IsTrue(HasItemText(mLayout, 'implizit'));
  Assert.IsTrue(HasItemText(mLayout, 'crDefault'));
  Assert.IsTrue(HasItemText(mLayout, 'nodefault'));
  Assert.IsTrue(HasItemText(mLayout, 'stored False'));
  Assert.IsTrue(HasItemText(mLayout, '+ 1 weitere Properties'));
  Assert.IsFalse(HasItemText(mLayout, 'Width'), 'achte Zeile erst nach dem Klick');
  Assert.IsTrue(HasItemText(mLayout, 'Controls[Index: Integer]'));
  Assert.IsTrue(HasItemText(mLayout, 'Standard-Property'));
  Assert.IsTrue(HasItemText(mLayout, 'Liste'), 'Strg+C kopiert die Liste');
  // Ereignis am Methodenzeiger-Typ erkannt: kenntlich, wenn der Typname es nicht verrät.
  Assert.IsFalse(HasItemText(mLayout, '(of object)'), 'OnRueckmeldung steht erst hinter „+ 1 weitere“');
  mHoverView.Toggle(TAtlasHoverPublishedToggle.MoreProperties);
  mHoverView.Toggle(TAtlasHoverPublishedToggle.MoreEvents);
  mHoverInput.View := mHoverView;
  mLayout := BuildLayout(mHoverInput);
  Assert.IsTrue(HasItemText(mLayout, 'Width'));
  Assert.IsTrue(HasItemText(mLayout, '(of object)'));
  Assert.AreEqual('0123', PublishedCodes(mLayout));
  // Ohne geerbte: nur die zwei eigenen Properties und das eigene Ereignis.
  mHoverView.Toggle(TAtlasHoverPublishedToggle.ShowInherited);
  mHoverInput.View := mHoverView;
  mLayout := BuildLayout(mHoverInput);
  Assert.IsTrue(HasItemText(mLayout, 'Cancel'));
  Assert.IsFalse(HasItemText(mLayout, 'Cursor'));
  Assert.IsFalse(HasItemText(mLayout, 'OnClick'));
  Assert.IsTrue(HasItemText(mLayout, 'OnRueckmeldung'));
  // Zugeklappt: nur der Titel.
  mHoverView.Toggle(TAtlasHoverPublishedToggle.ShowInherited);
  mHoverView.Toggle(TAtlasHoverPublishedToggle.Properties);
  mHoverInput.View := mHoverView;
  mLayout := BuildLayout(mHoverInput);
  Assert.IsTrue(HasItemText(mLayout, 'PROPERTIES ▸'));
  Assert.IsFalse(HasItemText(mLayout, 'Cancel'));
  Assert.IsTrue(HasItemText(mLayout, 'OnClick'));
  // Nur mit default: Cancel, Default, Cursor.
  mHoverView.Toggle(TAtlasHoverPublishedToggle.Properties);
  mHoverView.Toggle(TAtlasHoverPublishedToggle.OnlyDefaults);
  mHoverInput.View := mHoverView;
  mLayout := BuildLayout(mHoverInput);
  Assert.IsTrue(HasItemText(mLayout, 'Cursor'));
  Assert.IsFalse(HasItemText(mLayout, 'Height'));
  Assert.IsFalse(HasItemText(mLayout, 'Hint'));
end;

procedure THoverLayoutMembersTests.PublishedMembersAsTables;
var
  mHoverView: TAtlasHoverView;
  mHoverInput: TAtlasHoverInput;
  mLayout: TAtlasHoverLayout;
  mHint: TAtlasHoverMember;
begin
  mHoverView := ActionsView;
  mHoverView.Data.Location.Name := 'TKnopf';
  mHint := Member('Hint', 'string', 'TControl', hdNone, '');
  mHint.Stored := 'False';
  mHoverView.Data.Members := [Member('Cancel', 'Boolean', 'TKnopf', hdImplicit, 'False'),
    Member('Default', 'Boolean', 'TKnopf', hdImplicit, 'False'),
    Member('Cursor', 'TCursor', 'TControl', hdExplicit, 'crDefault'),
    Member('Height', 'Integer', 'TControl', hdNoDefault, ''), mHint,
    Member('Left', 'Integer', 'TControl', hdNone, ''), Member('Top', 'Integer', 'TControl', hdNone, ''),
    Member('Width', 'Integer', 'TControl', hdNone, ''),
    EventMember('OnClick', 'TNotifyEvent', 'TControl'), EventMember('OnEnter', 'TNotifyEvent', 'TWinControl'),
    EventMember('OnKeyDown', 'TKeyEvent', 'TWinControl'), EventMember('OnExit', 'TNotifyEvent', 'TWinControl'),
    EventMember('OnRueckmeldung', 'TMeinRueckruf', 'TKnopf')];
  mHoverView.Data.DefaultProperty := 'Controls[Index: Integer]: TControl';
  mHoverInput := HoverTestInput(mHoverView, 460);
  mHoverInput.Texts.PublishedSummary := 'published: %d Properties · %d Ereignisse';
  mHoverInput.Texts.PublishedInherited := 'geerbte';
  mHoverInput.Texts.PublishedOnlyDefaults := 'nur mit default';
  mHoverInput.Texts.PublishedProperties := 'Properties';
  mHoverInput.Texts.PublishedEvents := 'Ereignisse';
  mHoverInput.Texts.PublishedName := 'Name';
  mHoverInput.Texts.PublishedImplicit := 'implizit';
  mHoverInput.Texts.PublishedMoreProperties := '+ %d weitere Properties';
  mHoverInput.Texts.PublishedMoreEvents := '+ %d weitere Ereignisse';
  mHoverInput.Texts.PublishedArrayProperty := 'Array-Property';
  mHoverInput.Texts.PublishedDefaultProperty := 'Standard-Property';
  mHoverInput.Texts.PublishedCopyList := 'Liste';
  mLayout := BuildLayout(mHoverInput);
  AssertPublishedToggles(mHoverView, mHoverInput, mLayout);
  // Ohne Mitglieder kein Abschnitt.
  mLayout := BuildLayout(HoverTestInput(ActionsView, 460));
  Assert.AreEqual('', PublishedCodes(mLayout));
end;

/// <summary>Komponente mit 40 Properties, alle gezeigt.</summary>
function ManyMembersInput(AMaxLines, ALimit, AScroll: Integer): TAtlasHoverInput;
var
  mView: TAtlasHoverView;
  mIndex: Integer;
begin
  mView := ActionsView;
  mView.Data.Members := nil;
  SetLength(mView.Data.Members, 40);
  for mIndex := 0 to 39 do
  begin
    mView.Data.Members[mIndex] := Member('P' + IntToStr(mIndex), 'Integer', 'TControl', hdNone, '');
  end;
  mView.AllProperties := True;
  Result := Default(TAtlasHoverInput);
  Result.View := mView;
  Result.Width := 460;
  Result.PPI := 96;
  Result.Colors := TAtlasColors.Light;
  Result.Texts.PublishedSummary := 'published: %d Properties · %d Ereignisse';
  Result.Texts.PublishedProperties := 'Properties';
  Result.Members.MaxLines := AMaxLines;
  Result.Members.Limit := ALimit;
  Result.Members.Scroll := AScroll;
end;

/// <summary>Obere Kante des Bausteins mit Text AText; -1 ohne.</summary>
function ItemTop(const ALayout: TAtlasHoverLayout; const AText: string): Integer;
var
  mItem: TAtlasHoverItem;
begin
  for mItem in ALayout.Items do
  begin
    if mItem.Text = AText then
    begin
      Exit(mItem.Rect.Top);
    end;
  end;
  Result := -1;
end;

procedure THoverLayoutMembersTests.PublishedMembersScroll;
var
  mFull, mLayout: TAtlasHoverLayout;
begin
  // Ohne Grenze: kein Rollbereich, alles sichtbar.
  mFull := BuildLayout(ManyMembersInput(0, 0, 0));
  Assert.IsFalse(mFull.Members.Scrollable);
  Assert.AreEqual(-1, mFull.Members.ClipFrom);
  Assert.AreEqual(mFull.Members.Content, mFull.Members.View.Height);
  // Fünf Zeilen zu je 16 + 3 Pixeln.
  mLayout := BuildLayout(ManyMembersInput(5, 0, 0));
  Assert.IsTrue(mLayout.Members.Scrollable);
  Assert.AreEqual(95, mLayout.Members.View.Height);
  Assert.AreEqual(19, mLayout.Members.Row);
  Assert.AreEqual(mFull.Members.Content, mLayout.Members.Content);
  Assert.AreEqual(mFull.Height - mFull.Members.Content + 95, mLayout.Height);
  Assert.IsTrue((mLayout.Members.ClipFrom >= 0) and (mLayout.Members.ClipTill > mLayout.Members.ClipFrom));
  // Daumen nach dem beschnittenen Bereich am rechten Rand.
  Assert.AreEqual(Ord(TAtlasHoverItemKind.RoundFill), Ord(mLayout.Items[mLayout.Members.ClipTill].Kind));
  Assert.AreEqual(453, mLayout.Items[mLayout.Members.ClipTill].Rect.Left);
  Assert.AreEqual(mLayout.Members.View.Top, mLayout.Items[mLayout.Members.ClipTill].Rect.Top);
  // Bildschirm enger als die Zeilen: die kleinere Grenze, mindestens drei Zeilen.
  Assert.AreEqual(60, BuildLayout(ManyMembersInput(5, 60, 0)).Members.View.Height);
  Assert.AreEqual(57, BuildLayout(ManyMembersInput(5, 20, 0)).Members.View.Height);
  Assert.AreEqual(57, BuildLayout(ManyMembersInput(0, 20, 0)).Members.View.Height);
  // Versatz verschiebt die Zeilen, zu großer Versatz wird begrenzt.
  mLayout := BuildLayout(ManyMembersInput(5, 0, 38));
  Assert.AreEqual(38, mLayout.Members.Scroll);
  Assert.AreEqual(ItemTop(mFull, 'P5') - 38, ItemTop(mLayout, 'P5'));
  mLayout := BuildLayout(ManyMembersInput(5, 0, 100000));
  Assert.AreEqual(mLayout.Members.MaxScroll, mLayout.Members.Scroll);
  Assert.AreEqual(mLayout.Members.View.Bottom, mLayout.Items[mLayout.Members.ClipTill].Rect.Bottom);
end;

procedure THoverLayoutMembersTests.ScrolledMembersDropHiddenHits;
var
  mLayout: TAtlasHoverLayout;
  mHit: TAtlasHoverHit;
begin
  // Oben: Schalter (0, 1) und Abschnittstitel (2); ganz unten gescrollt ist der Titel verschwunden.
  mLayout := BuildLayout(ManyMembersInput(5, 0, 0));
  Assert.AreEqual('012', PublishedCodes(mLayout));
  mLayout := BuildLayout(ManyMembersInput(5, 0, 100000));
  Assert.AreEqual('01', PublishedCodes(mLayout));
  for mHit in mLayout.Hits do
  begin
    if (mHit.Kind = TAtlasHoverHitKind.Published) and (mHit.Rect.Top >= mLayout.Members.View.Top) then
    begin
      Assert.IsTrue(mHit.Rect.Bottom <= mLayout.Members.View.Bottom);
    end;
  end;
end;


procedure THoverLayoutMembersTests.PainterWithoutMembersAddsNothing;
var
  mProbe: TMembersProbe;
begin
  mProbe := TMembersProbe.Create(HoverTestInput(ActionsView, 460), TFakeMeasure.Create('x'));
  try
    Assert.AreEqual(10, mProbe.Run);
    Assert.AreEqual(0, mProbe.ItemCount);
  finally
    mProbe.Free;
  end;
end;

procedure THoverLayoutMembersTests.PainterShowsDefaultPropertyOnly;
var
  mView: TAtlasHoverView;
  mInput: TAtlasHoverInput;
  mProbe: TMembersProbe;
begin
  mView := ActionsView;
  mView.Data.DefaultProperty := 'Items[Index: Integer]: string';
  mInput := HoverTestInput(mView, 460);
  mInput.Texts.PublishedDefaultProperty := 'Standard-Property';
  mProbe := TMembersProbe.Create(mInput, TFakeMeasure.Create('x'));
  try
    Assert.IsTrue(mProbe.Run > 10);
    Assert.IsTrue(mProbe.Shows('Standard-Property'));
  finally
    mProbe.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(THoverLayoutMembersTests);

end.
