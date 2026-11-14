unit Atlas.Core.Hover.Layout.TestSupport;

// Gemeinsames der Tests des Hover-Satzes: Messung mit festen Werten (Breite je Zeichen UI 7, Editorschrift 8,
// halbfett 9, klein 6; Zeilenhöhe UI 15, Editorschrift 16, klein UI 13, klein Editorschrift 12), kurze Texte,
// Eingabe bei 96 dpi und eine Ansicht mit Fundstelle.

interface

uses
  System.Types,
  Atlas.Core.Hover.Items,
  Atlas.Core.Hover.Layout,
  Atlas.Core.Hover.Layout.Contract,
  Atlas.Core.Hover.View,
  Atlas.Core.Hover.Texts;

type
  /// <summary>Messung der Tests mit festen Werten je Schrift.</summary>
  TFakeMeasure = class(TInterfacedObject, IAtlasHoverMeasure)
  private
    FDeclaration: string;
    function Cum: TArray<Integer>;
  public
    constructor Create(const ADeclaration: string);
    function TextWidth(const AFace: TAtlasHoverFace; const AText: string): Integer;
    function TextHeight(const AFace: TAtlasHoverFace): Integer;
    function BlockHeight(const AText: string; AWidth: Integer): Integer;
    function DeclarationWidth(AFrom, ATill: Integer): Integer;
    function DeclarationLines(AWidth, AIndent: Integer): TArray<TPoint>;
  end;

/// <summary>Kurze Texte, an denen die Tests die Abschnitte erkennen.</summary>
function HoverTestTexts: TAtlasHoverTexts;
/// <summary>Eingabe für AView mit Breite AWidth bei 96 dpi, heller Farbe und den Texten der Tests.</summary>
function HoverTestInput(const AView: TAtlasHoverView; AWidth: Integer): TAtlasHoverInput;
/// <summary>Layout mit der Messung der Tests.</summary>
function BuildLayout(const AInput: TAtlasHoverInput): TAtlasHoverLayout;
/// <summary>Ansicht mit Fundstelle C:\a\U.pas, Zeile 4.</summary>
function ActionsView: TAtlasHoverView;

implementation

uses
  Atlas.Core.Hover.Contract,
  Atlas.Core.Style.Palette,
  Atlas.Core.Style.Wrap;

constructor TFakeMeasure.Create(const ADeclaration: string);
begin
  inherited Create;
  FDeclaration := ADeclaration;
end;

function TFakeMeasure.Cum: TArray<Integer>;
var
  mIndex: Integer;
begin
  Result := nil;
  SetLength(Result, Length(FDeclaration) + 1);
  for mIndex := 0 to Length(FDeclaration) do
  begin
    Result[mIndex] := 8 * mIndex;
  end;
end;

function TFakeMeasure.TextWidth(const AFace: TAtlasHoverFace; const AText: string): Integer;
begin
  case AFace.Font of
    TAtlasHoverFont.Ui:
      Result := 7 * Length(AText);
    TAtlasHoverFont.Mono:
      if AFace.Bold then
      begin
        Result := 9 * Length(AText);
      end
      else
      begin
        Result := 8 * Length(AText);
      end;
  else
    Result := 6 * Length(AText);
  end;
end;

function TFakeMeasure.TextHeight(const AFace: TAtlasHoverFace): Integer;
begin
  case AFace.Font of
    TAtlasHoverFont.Ui:
      Result := 15;
    TAtlasHoverFont.Mono:
      Result := 16;
    TAtlasHoverFont.SmallUi:
      Result := 13;
  else
    Result := 12;
  end;
end;

function TFakeMeasure.BlockHeight(const AText: string; AWidth: Integer): Integer;
begin
  Result := 15 * ((7 * Length(AText) + AWidth - 1) div AWidth);
end;

function TFakeMeasure.DeclarationWidth(AFrom, ATill: Integer): Integer;
begin
  Result := 8 * (ATill - AFrom);
end;

function TFakeMeasure.DeclarationLines(AWidth, AIndent: Integer): TArray<TPoint>;
begin
  Result := TAtlasWrap.AtSpaces(FDeclaration, Cum, AWidth, AIndent);
end;

function HoverTestTexts: TAtlasHoverTexts;
begin
  Result := Default(TAtlasHoverTexts);
  Result.Pinned := 'pinned';
  Result.Inheritance := 'Vererbung';
  Result.TargetType := 'Ziel %s';
  Result.Navigate := 'Go';
  Result.Usages := 'Us';
  Result.UsagesCount := '%d Us';
  Result.Copy := 'Cp';
  Result.CopySelection := 'Sel';
  Result.Help := 'H';
  Result.KeyUsages := 'U';
  Result.KeyCopy := 'C';
  Result.SourceAtlas := 'Atlas';
  Result.SourceCompiler := 'dcc';
  Result.SourceInactive := 'inaktiv';
  Result.Stale := 'alt';
  Result.DebugPending := 'eval';
  Result.DebugExplaining := 'sucht';
  Result.DebugChecked := 'geprüft';
  Result.ReassignedOne := 'einmal %s';
  Result.ReassignedCount := '%d mal %s';
end;

function HoverTestInput(const AView: TAtlasHoverView; AWidth: Integer): TAtlasHoverInput;
begin
  Result := Default(TAtlasHoverInput);
  Result.View := AView;
  Result.Width := AWidth;
  Result.PPI := 96;
  Result.Colors := TAtlasColors.Light;
  Result.Texts := HoverTestTexts;
end;

function BuildLayout(const AInput: TAtlasHoverInput): TAtlasHoverLayout;
begin
  Result := TAtlasHoverLayout.Build(AInput, TFakeMeasure.Create(AInput.View.Data.Declaration));
end;

function ActionsView: TAtlasHoverView;
var
  mData: TAtlasHoverData;
begin
  mData := Default(TAtlasHoverData);
  mData.Declaration := 'x';
  mData.Location.Name := 'x';
  mData.Location.FileName := 'C:\a\U.pas';
  mData.Location.Line := 4;
  Result := TAtlasHoverView.Create(mData);
end;

end.
