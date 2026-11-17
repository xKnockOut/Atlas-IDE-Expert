unit Atlas.Tests.EditSurfaceFake;

// Fälschung für IAtlasEditSurface: ein Text mit Rückgängig-Stapel, wie eine
// Bearbeitungssitzung den Editorpuffer der IDE sieht. Write wendet die
// Ersetzungen auf den aktuellen Text an und legt einen Schritt ab;
// TypeText spielt eine Änderung der IDE selbst (Einfügen, Vorschlag
// übernommen), ebenfalls als eigenen Schritt. Undo und Redo wandern im
// Stapel; mit UndoFails gibt es keinen Schritt zurück. OnWrite läuft nach
// jedem Write, etwa um eine IDE nachzustellen, die den Text anders schreibt
// als verlangt. Writes zählt die Schreibvorgänge, Paints das Neuzeichnen,
// Revealed ist die zuletzt sichtbar gemachte Zeile; Write setzt Modified. Write mit einem ABase, das
// nicht der aktuelle Text ist, löst EArgumentException aus: Der Schreiber der
// IDE würde dann an falschen Stellen schreiben.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Editor.EditSurface;

type
  TAtlasEditSurfaceFake = class(TInterfacedObject, IAtlasEditSurface)
  private
    FFileName: string;
    FText: string;
    FUndo: TList<string>;
    FRedo: TList<string>;
    FLine: Integer;
    FCharacter: Integer;
    FAnchorLine: Integer;
    FAnchorCharacter: Integer;
    FReadOnly: Boolean;
    FModified: Boolean;
    FTabWidth: Integer;
    FRevealed: Integer;
    FPaints: Integer;
    FUndoFails: Boolean;
    FWrites: Integer;
    FOnWrite: TProc;
    /// <summary>ANewText als neuen Schritt übernehmen.</summary>
    procedure Push(const ANewText: string);
  public
    constructor Create(const AFileName, AText: string);
    destructor Destroy; override;
    /// <summary>Cursor auf Zeile ALine, Zeichen ACharacter (ohne Markierung).</summary>
    procedure Caret(ALine, ACharacter: Integer);
    /// <summary>Markierung von ALine/ACharacter bis zum Cursor.</summary>
    procedure SelectFrom(ALine, ACharacter: Integer);
    /// <summary>Änderung der IDE selbst: ANewText als eigener Rückgängig-Schritt, Cursor auf ALine/ACharacter.
    /// </summary>
    procedure TypeText(const ANewText: string; ALine, ACharacter: Integer);
    /// <summary>Text ersetzen, ohne einen Schritt abzulegen (Schreiben, das anders ausgeht als verlangt).</summary>
    procedure Overwrite(const ANewText: string);
    /// <summary>Zahl der Schritte, die Undo zurücknehmen kann.</summary>
    function UndoDepth: Integer;
    { IAtlasEditSurface }
    function FileName: string;
    function IsReadOnly: Boolean;
    function IsModified: Boolean;
    function TabWidth: Integer;
    function Text: string;
    function LineText(ALine: Integer): string;
    function HasSelection: Boolean;
    procedure ReadCaret(out ALine, ACharacter: Integer);
    procedure WriteCaret(ALine, ACharacter: Integer);
    procedure ReadSelection(out AAnchorLine, AAnchorCharacter, ALine, ACharacter: Integer);
    procedure WriteSelection(AAnchorLine, AAnchorCharacter, ALine, ACharacter: Integer);
    procedure Reveal(ALine: Integer);
    procedure Paint;
    procedure Write(const ABase: string; const AEdits: TAtlasTextEdits);
    function Undo: Boolean;
    function Redo: Boolean;
    property ReadOnly: Boolean read FReadOnly write FReadOnly;
    property Modified: Boolean read FModified write FModified;
    property Tabs: Integer read FTabWidth write FTabWidth;
    property Revealed: Integer read FRevealed;
    property Paints: Integer read FPaints;
    property UndoFails: Boolean read FUndoFails write FUndoFails;
    property Writes: Integer read FWrites;
    property OnWrite: TProc read FOnWrite write FOnWrite;
  end;

implementation

uses
  Atlas.Text.Lines;

{ TAtlasEditSurfaceFake }

constructor TAtlasEditSurfaceFake.Create(const AFileName, AText: string);
begin
  inherited Create;
  FFileName := AFileName;
  FText := AText;
  FUndo := TList<string>.Create;
  FRedo := TList<string>.Create;
  FTabWidth := 2;
  FRevealed := -1;
end;

destructor TAtlasEditSurfaceFake.Destroy;
begin
  FRedo.Free;
  FUndo.Free;
  inherited;
end;

procedure TAtlasEditSurfaceFake.Push(const ANewText: string);
begin
  FUndo.Add(FText);
  FRedo.Clear;
  FText := ANewText;
end;

procedure TAtlasEditSurfaceFake.Caret(ALine, ACharacter: Integer);
begin
  FLine := ALine;
  FCharacter := ACharacter;
  FAnchorLine := ALine;
  FAnchorCharacter := ACharacter;
end;

procedure TAtlasEditSurfaceFake.SelectFrom(ALine, ACharacter: Integer);
begin
  FAnchorLine := ALine;
  FAnchorCharacter := ACharacter;
end;

procedure TAtlasEditSurfaceFake.TypeText(const ANewText: string; ALine, ACharacter: Integer);
begin
  Push(ANewText);
  Caret(ALine, ACharacter);
end;

procedure TAtlasEditSurfaceFake.Overwrite(const ANewText: string);
begin
  FText := ANewText;
end;

function TAtlasEditSurfaceFake.UndoDepth: Integer;
begin
  Result := FUndo.Count;
end;

function TAtlasEditSurfaceFake.FileName: string;
begin
  Result := FFileName;
end;

function TAtlasEditSurfaceFake.IsReadOnly: Boolean;
begin
  Result := FReadOnly;
end;

function TAtlasEditSurfaceFake.IsModified: Boolean;
begin
  Result := FModified;
end;

function TAtlasEditSurfaceFake.TabWidth: Integer;
begin
  Result := FTabWidth;
end;

function TAtlasEditSurfaceFake.Text: string;
begin
  Result := FText;
end;

function TAtlasEditSurfaceFake.LineText(ALine: Integer): string;
begin
  Result := TTextLines.LineAt(TTextLines.SplitLines(FText), ALine);
end;

function TAtlasEditSurfaceFake.HasSelection: Boolean;
begin
  Result := (FAnchorLine <> FLine) or (FAnchorCharacter <> FCharacter);
end;

procedure TAtlasEditSurfaceFake.ReadCaret(out ALine, ACharacter: Integer);
begin
  ALine := FLine;
  ACharacter := FCharacter;
end;

procedure TAtlasEditSurfaceFake.WriteCaret(ALine, ACharacter: Integer);
begin
  Caret(ALine, ACharacter);
  Paint;
end;

procedure TAtlasEditSurfaceFake.ReadSelection(out AAnchorLine, AAnchorCharacter, ALine, ACharacter: Integer);
begin
  AAnchorLine := FAnchorLine;
  AAnchorCharacter := FAnchorCharacter;
  ALine := FLine;
  ACharacter := FCharacter;
end;

procedure TAtlasEditSurfaceFake.WriteSelection(AAnchorLine, AAnchorCharacter, ALine, ACharacter: Integer);
begin
  Caret(ALine, ACharacter);
  SelectFrom(AAnchorLine, AAnchorCharacter);
end;

procedure TAtlasEditSurfaceFake.Reveal(ALine: Integer);
begin
  FRevealed := ALine;
end;

procedure TAtlasEditSurfaceFake.Paint;
begin
  Inc(FPaints);
end;

procedure TAtlasEditSurfaceFake.Write(const ABase: string; const AEdits: TAtlasTextEdits);
var
  mText: string;
  mIndex: Integer;
begin
  // Der Schreiber der IDE rechnet mit den Versätzen aus ABase im aktuellen Puffer: beide müssen gleich sein.
  if ABase <> FText then
  begin
    raise EArgumentException.Create('Write: ABase ist nicht der Text des Puffers');
  end;
  mText := FText;
  for mIndex := High(AEdits) downto 0 do
  begin
    mText := Copy(mText, 1, AEdits[mIndex].Start) + AEdits[mIndex].Insert +
      Copy(mText, AEdits[mIndex].Start + AEdits[mIndex].Count + 1, MaxInt);
  end;
  Push(mText);
  FModified := True;
  Inc(FWrites);
  if Assigned(FOnWrite) then
  begin
    FOnWrite();
  end;
end;

function TAtlasEditSurfaceFake.Undo: Boolean;
begin
  Result := not FUndoFails and (FUndo.Count > 0);
  if Result then
  begin
    FRedo.Add(FText);
    FText := FUndo[FUndo.Count - 1];
    FUndo.Delete(FUndo.Count - 1);
  end;
end;

function TAtlasEditSurfaceFake.Redo: Boolean;
begin
  Result := FRedo.Count > 0;
  if Result then
  begin
    FUndo.Add(FText);
    FText := FRedo[FRedo.Count - 1];
    FRedo.Delete(FRedo.Count - 1);
  end;
end;

end.
