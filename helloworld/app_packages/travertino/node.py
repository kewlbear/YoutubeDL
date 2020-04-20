

def set_root(node, root):
    # Propegate a root node change through a tree.
    node._root = root
    for child in node.children:
        set_root(child, root)


class Node:
    def __init__(self, style, applicator=None, children=None):
        self.applicator = applicator
        self.style = style.copy(applicator)
        self.intrinsic = self.style.IntrinsicSize()
        self.layout = self.style.Box(self)

        self._parent = None
        self._root = None
        if children is None:
            self._children = None
        else:
            self._children = []
            for child in children:
                self.add(child)

    @property
    def root(self):
        """The root of the tree containing this node.

        Returns:
            The root node. Returns self if this node *is* the root node.
        """
        return self._root if self._root else self

    @property
    def parent(self):
        """ The parent of this node.

        Returns:
            The parent of this node. Returns None if this node is the root node.
        """
        return self._parent

    @property
    def children(self):
        """ The children of this node.
        This *always* returns a list, even if the node is a leaf
        and cannot have children.

        Returns:
            A list of the children for this widget.
        """
        if self._children is None:
            return []
        else:
            return self._children

    @property
    def can_have_children(self):
        """Determine if the node can have children.

        This does not resolve whether there actually *are* any children;
        it only confirms whether children are theoretically allowed.
        """
        return self._children is not None

    def add(self, child):
        """Add a node as a child of this one.
        Args:
            child: A node to add as a child to this node.

        Raises:
            ValueError: If this node is a leaf, and cannot have children.
        """
        if self._children is None:
            raise ValueError('Cannot add children')

        self._children.append(child)
        child._parent = self
        set_root(child, self.root)

    def refresh(self, viewport):
        """Refresh the layout and appearance of the tree this node is contained in."""
        if self._root:
            self._root.refresh(viewport)
        else:
            self.style.layout(self, viewport)
            if self.applicator:
                self.applicator.set_bounds()
