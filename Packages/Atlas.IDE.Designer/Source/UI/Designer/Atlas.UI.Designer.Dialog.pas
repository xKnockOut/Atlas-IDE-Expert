unit Atlas.UI.Designer.Dialog;

// Gemeinsames Gerüst der kleinen Dialoge des Designers, reine VCL. Erbt von
// TAtlasDialog (Dialogschrift, Position, IDE-Thema samt Wechsel) und ergänzt
// den Rahmen je Dialog, Zeilen als TFlowPanel (Höhe nach Inhalt) und den
// skalierten Abstand. Die Dialoge erben davon statt dieselben Zeilen je
// Dialog zu wiederholen.

interface

uses
  System.Classes,
  System.UITypes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.ExtCtrls,
  Vcl.StdCtrls,
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
    function AddFlowLabel(AParent: TWinControl; const ACaption: string): TLabel;
    /// <summary>Breite eines Kontroll- oder Optionsfelds mit ACaption: Kästchen und Text.</summary>
    function CheckWidth(const ACaption: string): Integer;
    /// <summary>Knopf ACaption in AParent mit Ergebnis AResult, ausgerichtet nach AAlign mit Rand.</summary>
    function AddButton(AParent: TWinControl; const ACaption: string; AResult: TModalResult; AAlign: TAlign): TButton;
  public
    /// <summary>Leeren Dialog mit Titel ACaption, Innenbreite AWidth96 (logische Pixel) und Rahmen ABorder
    /// anlegen.</summary>
    constructor CreateDesignerDialog(AOwner: TComponent; const ACaption: string; AWidth96: Integer;
      ABorder: TFormBorderStyle);
  end;

implementation

const
  /// <summary>Abstand der Beschriftung nach oben, damit sie auf der Textzeile eines Eingabefelds steht.</summary>
  cLabelTop = 3;
  /// <summary>Kästchen eines Kontroll- oder Optionsfelds samt Abstand zum Text, logische Pixel.</summary>
  cCheckBox = 24;

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

function TAtlasDesignerDialog.AddFlowLabel(AParent: TWinControl; const ACaption: string): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.AlignWithMargins := True;
  Result.Margins.SetBounds(0, ScaleValue(cLabelTop), Gap div 2, 0);
end;

function TAtlasDesignerDialog.CheckWidth(const ACaption: string): Integer;
begin
  Result := Canvas.TextWidth(ACaption) + ScaleValue(cCheckBox);
end;

function TAtlasDesignerDialog.AddButton(AParent: TWinControl; const ACaption: string; AResult: TModalResult;
  AAlign: TAlign): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.ModalResult := AResult;
  Result.Align := AAlign;
  Result.AlignWithMargins := True;
end;

end.
