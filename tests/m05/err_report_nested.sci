#! error: DomainError
function level3()
  error("DomainError", "from level 3")
end
function level2() return level3() end
function level1()
  return level2()
end
level1()
