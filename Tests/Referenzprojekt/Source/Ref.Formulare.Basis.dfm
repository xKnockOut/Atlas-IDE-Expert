object BasisFormular: TBasisFormular
  Left = 0
  Top = 0
  Caption = 'Basis'
  ClientHeight = 300
  ClientWidth = 400
  object KopfPanel: TPanel
    Left = 0
    Top = 0
    Width = 400
    Height = 41
    Align = alTop
    TabOrder = 0
    object TitelLabel: TLabel
      Left = 8
      Top = 12
      Width = 30
      Height = 15
      Caption = 'Titel'
    end
    object SchliessenButton: TButton
      Left = 312
      Top = 8
      Width = 75
      Height = 25
      Caption = 'Schlie'#223'en'
      TabOrder = 0
      OnClick = SchliessenButtonClick
    end
  end
end
