import SwiftSoup

// A really bad implementation of HTML to Markdown. Only works with a few Markdown tags, but these seem to be the only
// ones used by the Performer Bio html sections on jococruise.com and sched.com.
//
// Any HTML tags not recognized and converted into their Markdown equivalent are removed from the output.
func markdown(fromHTML rootNode: Node) throws -> String {
	let accum = StringBuilder()
	var nextNode: Node = rootNode
	var parentStack: [(Node, String)] = [(rootNode, "")]

	traversal: while true {
		let curNode = nextNode
		var tailText: String = ""
		if let textNode = curNode as? TextNode {
			accum.append(textNode.getWholeText())
		} else if let element = (curNode as? Element) {
			switch element.tagName() {
				case "strong": accum.append("**"); tailText = "**"
				case "i", "em": accum.append("*"); tailText = "*"
				case "p": tailText = "\n"
				case "br": accum.append("\n")
				case "a": accum.append("["); tailText = try "](\(element.attr("href")))"
				default: break
			}
		}
		if curNode.childNodeSize() > 0 {
			nextNode = curNode.childNode(0)
			parentStack.append((curNode, tailText))
		} else {
			accum.append(tailText)
			while true {
				if let node = nextNode.nextSibling() {
					nextNode = node
					break
				}
				if parentStack.isEmpty {
					break traversal
				}
				else {
					var tail: String
					(nextNode, tail) = parentStack.removeLast()
					accum.append(tail)
				}
			}
		}
	}
	return accum.toString()
}
