unit Atlas.Core.Hover.Layout.Members;

// published-Mitglieder einer Komponentenklasse im Hover (#110): Übersicht „published: n Properties · m Ereignisse“
// mit den Schaltern „geerbte“ und „nur mit default“, die Tabellen PROPERTIES und EREIGNISSE (auf- und zuklappbar,
// gekürzt mit „+ n weitere …“), die Standard-Property und der Rollbereich mit Daumen (#1841).

interface

uses
  System.Types,
  Atlas.Core.Style.Color,
  Atlas.Core.Hover.Contract,
  Atlas.Core.Hover.Items,
  Atlas.Core.Hover.View,
  Atlas.Core.Hover.Layout.Contract,
  Atlas.Core.Hover.Layout.Painter;

type
  /// <summary>Spalten der Tabelle der published-Mitglieder.</summary>
  TMemberColumns = record
    NameX: Integer;
    TypeX: Integer;
    DefaultX: Integer;
  end;

  /// <summary>Abschnitt Properties bzw. Ereignisse der published-Mitglieder.</summary>
  TMemberSection = record
    Events: Boolean;
    Caption: string;
    MoreFormat: string;
    Collapsed: Boolean;
    ShowAll: Boolean;
    Toggle: TAtlasHoverPublishedToggle;
    More: TAtlasHoverPublishedToggle;
    Limit: Integer;
  end;

  /// <summary>published-Mitglieder einer Komponentenklasse (#110).</summary>
  TAtlasHoverMembersPainter = class(TAtlasHoverPainter)
  private
    procedure ToggleChip(const ACaption: string; AOn: Boolean; AToggle: TAtlasHoverPublishedToggle; AX: Integer);
    /// <summary>Gerahmte Marke in kleiner Schrift ab FX; liefert ihr Rechteck.</summary>
    function Tag(const ACaption: string; ALineColor, ATextColor: TAtlasColor): TRect;
    function SectionOf(AEvents: Boolean): TMemberSection;
    procedure SectionHead(const ASection: TMemberSection);
    function MemberColumns(const ARows: TArray<Integer>; AShown: Integer): TMemberColumns;
    /// <summary>Vorgabe ab AX bis höchstens ALimit (dahinter steht „deklariert in“).</summary>
    procedure MemberDefault(const AMember: TAtlasHoverMember; AX, ALimit: Integer);
    procedure MemberRow(const AMember: TAtlasHoverMember; const AColumns: TMemberColumns; AEvents: Boolean);
    procedure MoreLinks(const ASection: TMemberSection; AHidden: Integer);
    procedure MemberSection(AEvents: Boolean);
    procedure PublishedSummary;
    procedure DefaultPropertyRow;
    /// <summary>Rollbereich ab ATop (Bausteine ab AFirstItem, Klickflächen ab AFirstHit) begrenzen.</summary>
    procedure ClipMembers(ATop, AFirstItem, AFirstHit: Integer);
  protected
    /// <summary>Rollbereich der published-Mitglieder (#1841).</summary>
    FMembers: TAtlasHoverScroll;
    /// <summary>published-Mitglieder mit Übersicht, Tabellen und Standard-Property.</summary>
    procedure PublishedMembers;
  public
    constructor Create(const AInput: TAtlasHoverInput; const AMeasure: IAtlasHoverMeasure);
  end;

implementation

uses
  Atlas.Core.Style.Palette,
  System.SysUtils,
  System.Math,
  System.StrUtils;

const
  /// <summary>So viele Zeilen zeigen die Tabellen der published-Mitglieder, bis „+ n weitere“ geklickt ist.
  /// </summary>
  cPropertyRows = 7;
  cEventRows = 4;

constructor TAtlasHoverMembersPainter.Create(const AInput: TAtlasHoverInput; const AMeasure: IAtlasHoverMeasure);
begin
  inherited Create(AInput, AMeasure);
  FMembers := TAtlasHoverScroll.None;
end;

procedure TAtlasHoverMembersPainter.ToggleChip(const ACaption: string; AOn: Boolean;
  AToggle: TAtlasHoverPublishedToggle; AX: Integer);
var
  mTextFace: TAtlasHoverFace;
  mCell: TRect;
  mItem: TAtlasHoverItem;
  mLineColor, mTextColor: TAtlasColor;
begin
  // Schalter als umrandetes Kästchen: an in Akzentfarbe, aus gedämpft.
  mTextFace := TAtlasHoverFace.Create(TAtlasHoverFont.SmallUi, False, False);
  mCell := Rect(AX, FY, AX + Width(mTextFace, ACaption) + Scale(cAtlasChipPad), FY + Height(mTextFace) + Scale(2));
  if AOn then
  begin
    mLineColor := FColors.Accent;
    mTextColor := FColors.Accent;
  end
  else
  begin
    mLineColor := FColors.Line;
    mTextColor := FColors.Muted;
  end;
  mItem := NewItem(TAtlasHoverItemKind.Frame, mCell, mLineColor);
  mItem.Back := FColors.Surface;
  mItem.Radius := cAtlasChipRadius;
  MakeHot(mItem, TAtlasHoverHitKind.Published, Ord(AToggle), FColors.Accent);
  Add(mItem);
  mItem := NewItem(TAtlasHoverItemKind.CenterText, mCell, mTextColor);
  mItem.Text := ACaption;
  mItem.Face := mTextFace;
  MakeHot(mItem, TAtlasHoverHitKind.Published, Ord(AToggle), FColors.Accent);
  Add(mItem);
  AddHit(TAtlasHoverHitKind.Published, Ord(AToggle), mCell);
end;

function TAtlasHoverMembersPainter.Tag(const ACaption: string; ALineColor, ATextColor: TAtlasColor): TRect;
var
  mSmallFace: TAtlasHoverFace;
  mItem: TAtlasHoverItem;
begin
  mSmallFace := TAtlasHoverFace.Create(TAtlasHoverFont.SmallUi, False, False);
  Result := Rect(FX, FY + Scale(1), FX + Width(mSmallFace, ACaption) + Scale(cAtlasChipPad),
    FY + Height(mSmallFace) + Scale(3));
  mItem := NewItem(TAtlasHoverItemKind.Frame, Result, ALineColor);
  mItem.Back := FColors.Surface;
  mItem.Radius := cAtlasChipRadius;
  Add(mItem);
  mItem := NewItem(TAtlasHoverItemKind.CenterText, Result, ATextColor);
  mItem.Text := ACaption;
  mItem.Face := mSmallFace;
  Add(mItem);
end;

function TAtlasHoverMembersPainter.SectionOf(AEvents: Boolean): TMemberSection;
begin
  Result.Events := AEvents;
  if AEvents then
  begin
    Result.Caption := FInput.Texts.PublishedEvents;
    Result.MoreFormat := FInput.Texts.PublishedMoreEvents;
    Result.Collapsed := FInput.View.EventsCollapsed;
    Result.ShowAll := FInput.View.AllEvents;
    Result.Toggle := TAtlasHoverPublishedToggle.Events;
    Result.More := TAtlasHoverPublishedToggle.MoreEvents;
    Result.Limit := cEventRows;
  end
  else
  begin
    Result.Caption := FInput.Texts.PublishedProperties;
    Result.MoreFormat := FInput.Texts.PublishedMoreProperties;
    Result.Collapsed := FInput.View.PropertiesCollapsed;
    Result.ShowAll := FInput.View.AllProperties;
    Result.Toggle := TAtlasHoverPublishedToggle.Properties;
    Result.More := TAtlasHoverPublishedToggle.MoreProperties;
    Result.Limit := cPropertyRows;
  end;
end;

procedure TAtlasHoverMembersPainter.SectionHead(const ASection: TMemberSection);
var
  mCaption: string;
  mHeadFace: TAtlasHoverFace;
  mCell: TRect;
  mItem: TAtlasHoverItem;
begin
  // Abschnittstitel mit ▾ (offen) bzw. ▸ (zu); Klick klappt um.
  mHeadFace := TAtlasHoverFace.Create(TAtlasHoverFont.SmallMono, True, False);
  if ASection.Collapsed then
  begin
    mCaption := AnsiUpperCase(ASection.Caption) + ' ▸';
  end
  else
  begin
    mCaption := AnsiUpperCase(ASection.Caption) + ' ▾';
  end;
  mCell := Rect(FLeft, FY, FLeft + Width(mHeadFace, mCaption), FY + Height(mHeadFace));
  mItem := NewItem(TAtlasHoverItemKind.Text, mCell, FColors.Muted);
  mItem.Text := mCaption;
  mItem.Face := mHeadFace;
  MakeHot(mItem, TAtlasHoverHitKind.Published, Ord(ASection.Toggle), FColors.Accent);
  Add(mItem);
  AddHit(TAtlasHoverHitKind.Published, Ord(ASection.Toggle), mCell);
  Inc(FY, Height(mHeadFace) + Scale(5));
end;

function TAtlasHoverMembersPainter.MemberColumns(const ARows: TArray<Integer>; AShown: Integer): TMemberColumns;
var
  mRow, mGap: Integer;
  mMonoFace, mSmallFace: TAtlasHoverFace;
begin
  // Spalten nach den breitesten gezeigten Werten; „deklariert in“ rechtsbündig.
  mMonoFace := TAtlasHoverFace.Create(TAtlasHoverFont.Mono, False, False);
  mSmallFace := TAtlasHoverFace.Create(TAtlasHoverFont.SmallUi, False, False);
  mGap := Scale(12);
  Result.NameX := FLeft;
  Result.TypeX := Result.NameX + Width(mSmallFace, FInput.Texts.PublishedName);
  for mRow := 0 to AShown - 1 do
  begin
    Result.TypeX := Max(Result.TypeX, Result.NameX + Width(mMonoFace, FData.Members[ARows[mRow]].Name));
  end;
  Inc(Result.TypeX, mGap);
  Result.DefaultX := Result.TypeX + Width(mSmallFace, FInput.Texts.PublishedType);
  for mRow := 0 to AShown - 1 do
  begin
    Result.DefaultX := Max(Result.DefaultX, Result.TypeX + Width(mMonoFace, FData.Members[ARows[mRow]].TypeName));
  end;
  Inc(Result.DefaultX, mGap);
end;

procedure TAtlasHoverMembersPainter.MemberDefault(const AMember: TAtlasHoverMember; AX, ALimit: Integer);
var
  mMonoFace: TAtlasHoverFace;
  mTag: TRect;
begin
  mMonoFace := TAtlasHoverFace.Create(TAtlasHoverFont.Mono, False, False);
  FX := AX;
  if AMember.DefaultKind in [hdExplicit, hdImplicit] then
  begin
    // Lange Mengen ([akLeft, akTop] …) nicht in die Spalte „deklariert in“ laufen lassen.
    AddText(FX, FY, Clipped(mMonoFace, AMember.DefaultValue, ALimit - FX), mMonoFace, FColors.Text);
    Inc(FX, Width(mMonoFace, AMember.DefaultValue + ' '));
  end;
  if AMember.DefaultKind = hdImplicit then
  begin
    // Implizit als gedämpfte Marke.
    mTag := Tag(FInput.Texts.PublishedImplicit, FColors.Line, FColors.Muted);
    Inc(FX, mTag.Width + Scale(4));
  end
  else if AMember.DefaultKind = hdNoDefault then
  begin
    AddText(FX, FY, 'nodefault', mMonoFace, FColors.Muted);
    Inc(FX, Width(mMonoFace, 'nodefault '));
  end;
  if (AMember.Stored <> '') and (FX < ALimit) then
  begin
    AddText(FX, FY, Clipped(mMonoFace, 'stored ' + AMember.Stored, ALimit - FX), mMonoFace, FColors.Muted);
  end;
end;

procedure TAtlasHoverMembersPainter.MemberRow(const AMember: TAtlasHoverMember; const AColumns: TMemberColumns;
  AEvents: Boolean);
var
  mMonoFace, mSmallFace, mSmallMonoFace: TAtlasHoverFace;
begin
  mMonoFace := TAtlasHoverFace.Create(TAtlasHoverFont.Mono, False, False);
  mSmallFace := TAtlasHoverFace.Create(TAtlasHoverFont.SmallUi, False, False);
  mSmallMonoFace := TAtlasHoverFace.Create(TAtlasHoverFont.SmallMono, False, False);
  AddText(AColumns.NameX, FY, AMember.Name, mMonoFace, FColors.Text);
  AddText(AColumns.TypeX, FY, AMember.TypeName, mMonoFace, FColors.Accent);
  if not AEvents then
  begin
    MemberDefault(AMember, AColumns.DefaultX, FRight - Width(mSmallMonoFace, AMember.DeclaringClass) - Scale(8));
  end
  // Am Methodenzeiger-Typ erkannt, nicht am Namen: fremde Typnamen kenntlich machen.
  else if not EndsText('Event', AMember.TypeName) then
  begin
    AddText(AColumns.TypeX + Width(mMonoFace, AMember.TypeName + ' '),
      FY + (Height(mMonoFace) - Height(mSmallFace)) div 2, '(of object)', mSmallFace, FColors.Muted);
  end;
  AddText(FRight - Width(mSmallMonoFace, AMember.DeclaringClass),
    FY + (Height(mMonoFace) - Height(mSmallMonoFace)) div 2, AMember.DeclaringClass, mSmallMonoFace,
    FColors.Muted);
  Inc(FY, Height(mMonoFace) + Scale(3));
end;

procedure TAtlasHoverMembersPainter.MoreLinks(const ASection: TMemberSection; AHidden: Integer);
begin
  // „+ n weitere …“ zeigt alle; bei Ereignissen der Hinweis, woran sie erkannt sind.
  FX := FLeft;
  FRowHeight := 0;
  FFlowFont := TAtlasHoverFont.SmallUi;
  if AHidden > 0 then
  begin
    FlowLink(Format(ASection.MoreFormat, [AHidden]), FColors.Accent, TAtlasHoverHitKind.Published,
      Ord(ASection.More));
  end;
  if ASection.Events then
  begin
    if FX > FLeft then
    begin
      Flow(' · ', FColors.Muted, False);
    end;
    Flow(FInput.Texts.PublishedEventsNote, FColors.Muted, False);
  end;
  if FX > FLeft then
  begin
    Inc(FY, Scale(2));
    EndFlow;
  end;
  FFlowFont := TAtlasHoverFont.Ui;
end;

procedure TAtlasHoverMembersPainter.MemberSection(AEvents: Boolean);
var
  mRows: TArray<Integer>;
  mRow, mShown: Integer;
  mSection: TMemberSection;
  mColumns: TMemberColumns;
  mSmallFace: TAtlasHoverFace;
begin
  mRows := FData.VisibleMembers(AEvents, not FInput.View.HideInherited, FInput.View.OnlyDefaults);
  if Length(mRows) = 0 then
  begin
    Exit;
  end;
  mSection := SectionOf(AEvents);
  SectionHead(mSection);
  if mSection.Collapsed then
  begin
    Exit;
  end;
  mShown := Length(mRows);
  if not mSection.ShowAll then
  begin
    mShown := Min(mShown, mSection.Limit);
  end;
  mColumns := MemberColumns(mRows, mShown);
  if not AEvents then
  begin
    mSmallFace := TAtlasHoverFace.Create(TAtlasHoverFont.SmallUi, False, False);
    AddText(mColumns.NameX, FY, FInput.Texts.PublishedName, mSmallFace, FColors.Muted);
    AddText(mColumns.TypeX, FY, FInput.Texts.PublishedType, mSmallFace, FColors.Muted);
    AddText(mColumns.DefaultX, FY, FInput.Texts.PublishedDefault, mSmallFace, FColors.Muted);
    AddText(FRight - Width(mSmallFace, FInput.Texts.PublishedDeclared), FY, FInput.Texts.PublishedDeclared,
      mSmallFace, FColors.Muted);
    Inc(FY, Height(mSmallFace) + Scale(4));
  end;
  for mRow := 0 to mShown - 1 do
  begin
    MemberRow(FData.Members[mRows[mRow]], mColumns, AEvents);
  end;
  MoreLinks(mSection, Length(mRows) - mShown);
  Inc(FY, Scale(8));
end;

procedure TAtlasHoverMembersPainter.PublishedSummary;
var
  mSummary: string;
  mSmallFace: TAtlasHoverFace;
  mChipsWidth, mInheritedWidth: Integer;
begin
  // „published: 38 Properties · 24 Ereignisse“, rechts die Schalter; ohne Platz darunter.
  mSmallFace := TAtlasHoverFace.Create(TAtlasHoverFont.SmallUi, False, False);
  mSummary := Format(FInput.Texts.PublishedSummary, [FData.MemberCount(False), FData.MemberCount(True)]);
  mInheritedWidth := Width(mSmallFace, FInput.Texts.PublishedInherited) + Scale(cAtlasChipPad);
  mChipsWidth := mInheritedWidth + Scale(6) + Width(mSmallFace, FInput.Texts.PublishedOnlyDefaults) +
    Scale(cAtlasChipPad);
  AddText(FLeft, FY + Scale(1), mSummary, mSmallFace, FColors.Muted);
  if FLeft + Width(mSmallFace, mSummary) + Scale(12) + mChipsWidth > FRight then
  begin
    Inc(FY, Height(mSmallFace) + Scale(6));
  end;
  ToggleChip(FInput.Texts.PublishedInherited, not FInput.View.HideInherited,
    TAtlasHoverPublishedToggle.ShowInherited, FRight - mChipsWidth);
  ToggleChip(FInput.Texts.PublishedOnlyDefaults, FInput.View.OnlyDefaults, TAtlasHoverPublishedToggle.OnlyDefaults,
    FRight - mChipsWidth + mInheritedWidth + Scale(6));
  Inc(FY, Height(mSmallFace) + Scale(10));
end;

procedure TAtlasHoverMembersPainter.DefaultPropertyRow;
var
  mName, mNote: string;
  mSmallFace, mMonoFace, mHeadFace: TAtlasHoverFace;
  mBracket: Integer;
  mCell: TRect;
begin
  // Standard-Property: „default“ heißt an einer Array-Property nicht Vorgabewert.
  mSmallFace := TAtlasHoverFace.Create(TAtlasHoverFont.SmallUi, False, False);
  mMonoFace := TAtlasHoverFace.Create(TAtlasHoverFont.Mono, False, False);
  mHeadFace := TAtlasHoverFace.Create(TAtlasHoverFont.SmallMono, True, False);
  AddText(FLeft, FY, AnsiUpperCase(FInput.Texts.PublishedArrayProperty), mHeadFace, FColors.Muted);
  Inc(FY, Height(mHeadFace) + Scale(5));
  mName := FData.DefaultProperty;
  mBracket := Pos(']', mName);
  if mBracket > 0 then
  begin
    mName := Copy(mName, 1, mBracket);
  end;
  AddText(FLeft, FY, mName, mMonoFace, FColors.Text);
  FX := FLeft + Width(mMonoFace, mName + ' ');
  mCell := Tag(FInput.Texts.PublishedDefaultProperty, FColors.Accent, FColors.Accent);
  mNote := FInput.Texts.PublishedDefaultPropertyNote;
  if mCell.Right + Scale(8) + Width(mSmallFace, mNote) <= FRight then
  begin
    AddText(mCell.Right + Scale(8), FY + Scale(1), mNote, mSmallFace, FColors.Muted);
  end
  else
  begin
    Inc(FY, Height(mMonoFace) + Scale(3));
    AddText(FLeft, FY, mNote, mSmallFace, FColors.Muted);
  end;
  Inc(FY, Height(mMonoFace) + Scale(8));
end;

procedure TAtlasHoverMembersPainter.ClipMembers(ATop, AFirstItem, AFirstHit: Integer);
var
  mItem: TAtlasHoverItem;
begin
  // Rollbereich (#1841): Grenze aus Zeilen und Platz, Bausteine verschieben, verdeckte Klickflächen streichen.
  if not FMembers.Fit(FInput.Members, ATop, FY, FInput.Width,
    Height(TAtlasHoverFace.Create(TAtlasHoverFont.Mono, False, False)) + Scale(3)) then
  begin
    Exit;
  end;
  FMembers.Shift(FItems, AFirstItem, FItemCount, FHits, AFirstHit, FHitCount);
  mItem := NewItem(TAtlasHoverItemKind.RoundFill, FMembers.Thumb(Scale(16), Scale(7), Scale(3)),
    FColors.Muted);
  mItem.Radius := 2;
  Add(mItem);
  FY := FMembers.View.Bottom;
end;

procedure TAtlasHoverMembersPainter.PublishedMembers;
var
  mTop, mFirstItem, mFirstHit: Integer;
begin
  // published-Mitglieder einer Komponentenklasse (#110).
  if (Length(FData.Members) = 0) and (FData.DefaultProperty = '') then
  begin
    Exit;
  end;
  HorizontalLine(FY);
  Inc(FY, Scale(7));
  if Length(FData.Members) > 0 then
  begin
    PublishedSummary;
  end;
  // Tabellen und Standard-Property scrollen; Zusammenfassung und Schalter bleiben stehen.
  mTop := FY;
  mFirstItem := FItemCount;
  mFirstHit := FHitCount;
  if Length(FData.Members) > 0 then
  begin
    MemberSection(False);
    MemberSection(True);
  end;
  if FData.DefaultProperty <> '' then
  begin
    DefaultPropertyRow;
  end;
  ClipMembers(mTop, mFirstItem, mFirstHit);
  FX := FLeft;
end;

end.
