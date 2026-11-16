unit Atlas.UI.Designer.Dialog;

// Gemeinsames Gerüst der kleinen Dialoge des Designers, reine VCL. Erbt von
// TAtlasDialog (Dialogschrift, Position, IDE-Thema samt Wechsel) und ergänzt
// den Rahmen je Dialog, Zeilen als TFlowPanel (Höhe nach Inhalt) und den
// skalierten Abstand. Die Dialoge erben davon statt dieselben Zeilen je
// Dialog zu wiederholen.

interface

uses
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.ExtCtrls,
  Atlas.UI.Foundation.Dialog;

type
  TAtlasDesignerDialog = class(TAtlasDialog)
  protected const
    /// <summary>Abstand zwischen Rand, Zeilen und Knöpfen, logische Pixel.</summary>
    cGap = 10;
  protected
    /// <summary>cGap in Pixeln des Fensters.</summary>
    function Gap: Integer;
    /// <summary>Neue Zeile unter allen bisherigen (alTop, Höhe nach Inhalt).</summary>
    function AddFlowRow: TFlowPanel;
    /// <summary>Beschriftung ACaption in AParent, auf Höhe des Texts eines Eingabefelds daneben.</summary>
    procedure AddFlowLabel(AParent: TWinControl; const ACaption: string);
  public
    /// <summary>Leeren Dialog mit Titel ACaption, Innenbreite AWidth96 (logische Pixel) und Rahmen ABorder
    /// anlegen.</summary>
    constructor CreateDesignerDialog(AOwner: TComponent; const ACaption: string; AWidth96: Integer;
      ABorder: TFormBorderStyle);
  end;

implementation

uses
  Vcl.StdCtrls;

const
  /// <summary>Abstand der Beschriftung nach oben, damit sie auf der Textzeile eines Eingabefelds steht.</summary>
  cLabelTop = 3;

{ TAtlasDesignerDialog }

constructor TAtlasDesignerDialog.CreateDesignerDialog(AOwner: TComponent; const ACaption: string;
  AWidth96: Integer; ABorder: TFormBorderStyle);
begin
  inherited CreateDialog(AOwner, ACaption, AWidth96);
  BorderStyle := ABorder;
  // Breiten nach Text (Canvas.TextWidth) in der Dialogschrift.
  Canvas.Font := Font;
end;

function TAtlasDesignerDialog.Gap: Integer;
begin
  Result := ScaleValue(cGap);
end;

function TAtlasDesignerDialog.AddFlowRow: TFlowPanel;
var
  mTop: Integer;
begin
  mTop := NextTop;
  Result := TFlowPanel.Create(Self);
  // Lage vor Align und Parent: Sonst ordnet die VCL alTop-Zeilen beim Anlegen des Fensters nach der
  // vorläufigen Lage und kann die Reihenfolge vertauschen.
  Result.Top := mTop;
  Result.AutoSize := True;
  Result.BevelOuter := bvNone;
  Result.Caption := '';
  Result.AlignWithMargins := True;
  Result.Margins.SetBounds(Gap, Gap div 2, Gap, 0);
  Result.Align := alTop;
  Result.Parent := Self;
end;

procedure TAtlasDesignerDialog.AddFlowLabel(AParent: TWinControl; const ACaption: string);
var
  mLabel: TLabel;
begin
  mLabel := TLabel.Create(Self);
  mLabel.Parent := AParent;
  mLabel.Caption := ACaption;
  mLabel.AlignWithMargins := True;
  mLabel.Margins.SetBounds(0, ScaleValue(cLabelTop), Gap div 2, 0);
end;

end.
