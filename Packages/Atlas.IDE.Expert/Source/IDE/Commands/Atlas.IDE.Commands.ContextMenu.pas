unit Atlas.IDE.Commands.ContextMenu;

// Untermenü „Atlas“ im Kontextmenü des Editors (#399). Jedes Editorfenster
// der IDE hat ein eigenes Kontextmenü (Komponente „EditorLocalMenu“); Atlas
// hängt sein Untermenü ein, sobald ein Editorfenster gezeigt oder eine
// Ansicht aktiviert wird. Die Untermenüs merkt sich Atlas mit
// FreeNotification: Schließt die IDE ein Editorfenster, gibt sie sie mit frei.
// Beim Entladen nimmt Atlas alle wieder heraus.
// Tastenkürzel stehen nur als Text hinter einem Tab in der Beschriftung, nicht
// als ShortCut: Sonst würde das Kontextmenü die Taste ein zweites Mal
// auslösen. Beim Aufklappen werden die Beschriftungen nach den aktuellen
// Einstellungen erneuert.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Vcl.Forms,
  Vcl.Menus;

type
  TAtlasIdeContextMenu = class(TComponent)
  private type
    TEntry = record
      Caption: string;
      /// <summary>Tastenkürzel als TShortCut, 0 = keins; nil ohne Kürzel.</summary>
      Key: TFunc<Integer>;
      Proc: TProc;
    end;
  private const
    MenuName = 'EditorLocalMenu';
  private
    FEntries: TArray<TEntry>;
    FRoots: TList<TMenuItem>;
    function CaptionOf(AIndex: Integer): string;
    procedure ItemClick(Sender: TObject);
    procedure RootClick(Sender: TObject);
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create; reintroduce;
    destructor Destroy; override;
    /// <summary>Eintrag anhängen; ACaption '-' ist ein Trennstrich. AKey darf nil sein.</summary>
    procedure Add(const ACaption: string; const AKey: TFunc<Integer>; const AProc: TProc);
    /// <summary>Untermenü in das Kontextmenü von AForm einhängen, falls es dort fehlt.</summary>
    procedure Ensure(AForm: TCustomForm);
    /// <summary>Wie Ensure für alle offenen Editorfenster.</summary>
    procedure EnsureAll;
  end;

implementation

uses
  Atlas.Core.Diagnostics.Guard,
  Atlas.UI.Strings;

constructor TAtlasIdeContextMenu.Create;
begin
  inherited Create(nil);
  FRoots := TList<TMenuItem>.Create;
end;

destructor TAtlasIdeContextMenu.Destroy;
begin
  // Freigeben nimmt das Untermenü aus dem Kontextmenü; Notification entfernt es aus der Liste.
  while FRoots.Count > 0 do
    FRoots.Last.Free;
  FRoots.Free;
  inherited;
end;

procedure TAtlasIdeContextMenu.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if (Operation = opRemove) and (FRoots <> nil) and (AComponent is TMenuItem) then
    FRoots.Remove(TMenuItem(AComponent));
end;

procedure TAtlasIdeContextMenu.Add(const ACaption: string; const AKey: TFunc<Integer>; const AProc: TProc);
var
  Entry: TEntry;
begin
  Entry.Caption := ACaption;
  Entry.Key := AKey;
  Entry.Proc := AProc;
  FEntries := FEntries + [Entry];
end;

function TAtlasIdeContextMenu.CaptionOf(AIndex: Integer): string;
var
  Key: Integer;
begin
  Result := FEntries[AIndex].Caption;
  if not Assigned(FEntries[AIndex].Key) then
    Exit;
  Key := FEntries[AIndex].Key();
  if Key <> 0 then
    Result := Result + #9 + ShortCutToText(TShortCut(Key));
end;

procedure TAtlasIdeContextMenu.Ensure(AForm: TCustomForm);
var
  Menu: TComponent;
  Existing, Root, Item: TMenuItem;
  Index: Integer;
begin
  if AForm = nil then
    Exit;
  Menu := AForm.FindComponent(MenuName);
  if not (Menu is TPopupMenu) then
    Exit;
  for Existing in FRoots do
    if Existing.Parent = TPopupMenu(Menu).Items then
      Exit;
  Root := TMenuItem.Create(nil);
  Root.Caption := TAtlasStrings.Text(TAtlasTextId.MenuAtlas);
  Root.OnClick := RootClick;
  for Index := 0 to High(FEntries) do
  begin
    Item := TMenuItem.Create(Root);
    Item.Caption := CaptionOf(Index);
    Item.Tag := Index;
    if FEntries[Index].Caption <> '-' then
      Item.OnClick := ItemClick;
    Root.Add(Item);
  end;
  TPopupMenu(Menu).Items.Add(Root);
  Root.FreeNotification(Self);
  FRoots.Add(Root);
end;

procedure TAtlasIdeContextMenu.EnsureAll;
var
  Index: Integer;
begin
  for Index := 0 to Screen.FormCount - 1 do
    Ensure(Screen.Forms[Index]);
end;

procedure TAtlasIdeContextMenu.RootClick(Sender: TObject);
var
  Index: Integer;
  Root: TMenuItem;
begin
  try
    Root := TMenuItem(Sender);
    for Index := 0 to Root.Count - 1 do
      if (Root.Items[Index].Tag >= 0) and (Root.Items[Index].Tag <= High(FEntries)) then
        Root.Items[Index].Caption := CaptionOf(Root.Items[Index].Tag);
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.EditorCommands, E);
  end;
end;

procedure TAtlasIdeContextMenu.ItemClick(Sender: TObject);
var
  Index: Integer;
begin
  Index := TMenuItem(Sender).Tag;
  if (Index < 0) or (Index > High(FEntries)) or not Assigned(FEntries[Index].Proc) then
    Exit;
  TAtlasGuard.Run(TAtlasFeature.EditorCommands, FEntries[Index].Proc);
end;

end.
