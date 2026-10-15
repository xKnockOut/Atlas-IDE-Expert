unit Atlas.UI.Welcome.Board;

// Alle Atlas-Bereiche in einem Frame (#753): oben der Kopf (abschaltbar),
// darunter die Bereiche in Spalten nach TAtlasWelcomeLayout.Arrange. Im
// Atlas-Layout steht dieser Frame als ein Bereich „Atlas“ oben auf der
// Willkommensseite (zwei Spalten), im Fenster „Atlas-Start“ mit einer Spalte
// untereinander. Der Inhalt scrollt, wenn er höher ist als der Platz.
// Rebuild legt die Bereichs-Frames über TAtlasWelcomeViews an und behält
// vorhandene, solange ihr Bereich sichtbar bleibt.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Vcl.Controls,
  Vcl.Forms,
  Atlas.Core.Welcome.Sections,
  Atlas.Core.Welcome.Layout,
  Atlas.UI.Welcome.Frame,
  Atlas.UI.Welcome.Header;

type
  TAtlasWelcomeBoardFrame = class(TAtlasWelcomeFrame)
  public const
    Gap = 12;
  private
    FHeader: TAtlasWelcomeHeaderFrame;
    FScroll: TScrollBox;
    FViews: TObjectDictionary<string, TAtlasWelcomeSectionFrame>;
    FColumns: TArray<TArray<string>>;
    procedure ScrollResize(Sender: TObject);
    procedure Place;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>Bereiche neu verteilen: ASections (sichtbare, mit Titel) nach ALayout in AColumns Spalten.</summary>
    procedure Rebuild(const ASections: TArray<TAtlasWelcomeSection>; const ALayout: TAtlasWelcomeLayout;
      AColumns: Integer);
    /// <summary>Inhalt eines Bereichs nachführen; '' = alle.</summary>
    procedure UpdateSection(const AId: string);
    procedure UpdateContent; override;
    function View(const AId: string): TAtlasWelcomeSectionFrame;
    /// <summary>Kennungen je Spalte, wie zuletzt verteilt.</summary>
    property Columns: TArray<TArray<string>> read FColumns;
    property Header: TAtlasWelcomeHeaderFrame read FHeader;
  end;

implementation

{ TAtlasWelcomeBoardFrame }

constructor TAtlasWelcomeBoardFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FViews := TObjectDictionary<string, TAtlasWelcomeSectionFrame>.Create([doOwnsValues]);
  FHeader := TAtlasWelcomeHeaderFrame.Create(Self);
  FHeader.Parent := Self;
  FHeader.Align := alTop;
  FScroll := TScrollBox.Create(Self);
  FScroll.Parent := Self;
  FScroll.Align := alClient;
  FScroll.BorderStyle := bsNone;
  FScroll.ParentBackground := True;
  FScroll.VertScrollBar.Tracking := True;
  FScroll.OnResize := ScrollResize;
end;

destructor TAtlasWelcomeBoardFrame.Destroy;
begin
  // Die Bereichs-Frames gehören dem Wörterbuch, nicht dem Frame.
  FreeAndNil(FViews);
  inherited;
end;

function TAtlasWelcomeBoardFrame.View(const AId: string): TAtlasWelcomeSectionFrame;
begin
  if not FViews.TryGetValue(LowerCase(AId), Result) then
    Result := nil;
end;

procedure TAtlasWelcomeBoardFrame.Rebuild(const ASections: TArray<TAtlasWelcomeSection>;
  const ALayout: TAtlasWelcomeLayout; AColumns: Integer);
var
  Wanted: TDictionary<string, Boolean>;
  Section: TAtlasWelcomeSection;
  Key: string;
  Frame: TAtlasWelcomeSectionFrame;
begin
  FColumns := ALayout.Arrange(ASections, AColumns);
  Wanted := TDictionary<string, Boolean>.Create;
  try
    for Section in ASections do
    begin
      Key := LowerCase(Section.Id);
      Wanted.AddOrSetValue(Key, True);
      if not FViews.TryGetValue(Key, Frame) then
      begin
        // Ohne Besitzer: Das Wörterbuch gibt die Frames frei.
        Frame := TAtlasWelcomeViews.CreateView(Section.Id, nil);
        if Frame = nil then
          Continue;
        Frame.Parent := FScroll;
        FViews.Add(Key, Frame);
        Frame.UpdateContent;
      end;
      Frame.ShowTitle := True;
      Frame.Title := Section.Title;
    end;
    for Key in FViews.Keys.ToArray do
      if not Wanted.ContainsKey(Key) then
        FViews.Remove(Key);
  finally
    Wanted.Free;
  end;
  Place;
end;

procedure TAtlasWelcomeBoardFrame.ScrollResize(Sender: TObject);
begin
  Place;
end;

procedure TAtlasWelcomeBoardFrame.Place;
var
  Count, Column, Width, Left, Top: Integer;
  Id: string;
  Frame: TAtlasWelcomeSectionFrame;
begin
  Count := Length(FColumns);
  if Count = 0 then
    Exit;
  Width := (FScroll.ClientWidth - (Count + 1) * Gap) div Count;
  if Width < 120 then
    Width := 120;
  for Column := 0 to Count - 1 do
  begin
    Left := Gap + Column * (Width + Gap);
    Top := Gap - FScroll.VertScrollBar.Position;
    for Id in FColumns[Column] do
    begin
      Frame := View(Id);
      if Frame = nil then
        Continue;
      Frame.SetBounds(Left, Top, Width, Frame.PreferredHeight);
      Inc(Top, Frame.Height + Gap);
    end;
  end;
end;

procedure TAtlasWelcomeBoardFrame.UpdateSection(const AId: string);
var
  Frame: TAtlasWelcomeSectionFrame;
begin
  if AId = '' then
  begin
    for Frame in FViews.Values do
      Frame.UpdateContent;
    Place;
    Exit;
  end;
  Frame := View(AId);
  if Frame <> nil then
  begin
    Frame.UpdateContent;
    Place;
  end;
end;

procedure TAtlasWelcomeBoardFrame.UpdateContent;
begin
  UpdateSection('');
  inherited;
end;

end.
