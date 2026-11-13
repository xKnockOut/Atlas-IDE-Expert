unit Atlas.IDE.Designer.Tool;

// Gemeinsame Basis der Designer-Werkzeuge in der IDE: Meldungen in die
// Meldungsansicht (Say), Umrisse über dem Designer (Outlines, erst beim
// ersten Gebrauch angelegt) und Farben nach dem IDE-Thema (ApplyTheme).
// Vorher stand das wortgleich in jedem Werkzeug. Werkzeuge mit weiteren
// Fenstern ergänzen ApplyTheme. Nur im Hauptthread.

interface

uses
  Winapi.Windows,
  System.SysUtils,
  Vcl.Controls,
  Atlas.UI.Designer.Outlines;

type
  TAtlasIdeDesignerTool = class
  private
    FOnMessage: TProc<string>;
    FOutlines: TAtlasDesignerOutlines;
  protected
    /// <summary>Zeile in der Meldungsansicht.</summary>
    procedure Say(const AText: string); virtual;
    /// <summary>Umrisse über dem Designer; beim ersten Aufruf angelegt.</summary>
    function Outlines: TAtlasDesignerOutlines;
    /// <summary>Sind die Umrisse schon angelegt?</summary>
    function HasOutlines: Boolean;
    /// <summary>Umrisse AOutlines (Lage im Client von ARoot) über dem Client von ARoot zeigen.</summary>
    procedure ShowOutlinesIn(ARoot: TWinControl; const AOutlines: TArray<TAtlasOutline>);
    /// <summary>Fenster, dem die Fenster der Werkzeuge gehören (Hauptfenster der IDE).</summary>
    class function OwnerWindow: HWND; static;
    property OnMessage: TProc<string> read FOnMessage;
  public
    /// <summary>AOnMessage: Zeile in der Meldungsansicht (darf nil sein).</summary>
    constructor Create(const AOnMessage: TProc<string>);
    destructor Destroy; override;
    /// <summary>Farben nach dem IDE-Thema.</summary>
    procedure ApplyTheme; virtual;
  end;

implementation

uses
  Vcl.Forms,
  Atlas.IDE.Foundation.EditorStyle;

{ TAtlasIdeDesignerTool }

constructor TAtlasIdeDesignerTool.Create(const AOnMessage: TProc<string>);
begin
  inherited Create;
  FOnMessage := AOnMessage;
end;

destructor TAtlasIdeDesignerTool.Destroy;
begin
  FOutlines.Free;
  inherited Destroy;
end;

procedure TAtlasIdeDesignerTool.Say(const AText: string);
begin
  if Assigned(FOnMessage) then
  begin
    FOnMessage(AText);
  end;
end;

function TAtlasIdeDesignerTool.Outlines: TAtlasDesignerOutlines;
begin
  if FOutlines = nil then
  begin
    FOutlines := TAtlasDesignerOutlines.CreateOutlines(nil, OwnerWindow, TAtlasIdeStyle.Colors);
  end;
  Result := FOutlines;
end;

function TAtlasIdeDesignerTool.HasOutlines: Boolean;
begin
  Result := FOutlines <> nil;
end;

procedure TAtlasIdeDesignerTool.ShowOutlinesIn(ARoot: TWinControl; const AOutlines: TArray<TAtlasOutline>);
var
  mArea: TRect;
begin
  mArea := ARoot.ClientRect;
  mArea.Offset(ARoot.ClientOrigin);
  Outlines.ShowOutlines(mArea, AOutlines);
end;

class function TAtlasIdeDesignerTool.OwnerWindow: HWND;
begin
  Result := Application.MainFormHandle;
end;

procedure TAtlasIdeDesignerTool.ApplyTheme;
begin
  if FOutlines <> nil then
  begin
    FOutlines.ApplyColors(TAtlasIdeStyle.Colors);
  end;
end;

end.
