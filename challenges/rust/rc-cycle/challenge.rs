use std::rc::Rc;
use std::cell::RefCell;

// A doubly-linked list implementation with a critical memory safety bug.
// This implementation uses Rc for both forward and backward pointers,
// creating reference cycles that prevent proper cleanup.

type Link<T> = Option<Rc<RefCell<Node<T>>>>;

#[derive(Debug)]
struct Node<T> {
    value: T,
    next: Link<T>,
    prev: Link<T>,  // BUG: Rc prev creates reference cycles — use Weak instead
}

impl<T> Node<T> {
    fn new(value: T) -> Self {
        Node {
            value,
            next: None,
            prev: None,
        }
    }
}

struct DoublyLinkedList<T> {
    head: Link<T>,
    tail: Link<T>,
    len: usize,
}

impl<T> DoublyLinkedList<T> {
    fn new() -> Self {
        DoublyLinkedList {
            head: None,
            tail: None,
            len: 0,
        }
    }

    fn push_back(&mut self, value: T) {
        let new_node = Rc::new(RefCell::new(Node::new(value)));

        match self.tail.take() {
            None => {
                // First node: becomes both head and tail
                self.head = Some(new_node.clone());
                self.tail = Some(new_node);
            }
            Some(old_tail) => {
                // Link old tail's next to new node
                old_tail.borrow_mut().next = Some(new_node.clone());
                // Link new node's prev back to old tail (strong Rc reference)
                new_node.borrow_mut().prev = Some(old_tail);
                self.tail = Some(new_node);
            }
        }
        self.len += 1;
    }

    fn push_front(&mut self, value: T) {
        let new_node = Rc::new(RefCell::new(Node::new(value)));

        match self.head.take() {
            None => {
                // First node: becomes both head and tail
                self.head = Some(new_node.clone());
                self.tail = Some(new_node);
            }
            Some(old_head) => {
                // Link new node's next to old head
                new_node.borrow_mut().next = Some(old_head.clone());
                // Link old head's prev back to new node (strong Rc reference)
                old_head.borrow_mut().prev = Some(new_node.clone());
                self.head = Some(new_node);
            }
        }
        self.len += 1;
    }

    fn len(&self) -> usize {
        self.len
    }
}

impl<T> Drop for DoublyLinkedList<T> {
    fn drop(&mut self) {
        // Attempt to clean up, but reference cycles prevent proper cleanup.
        // The strong Rc pointers in the prev field keep nodes alive,
        // even when all user references are dropped.
        while let Some(node) = self.head.take() {
            self.head = node.borrow_mut().next.take();
        }
    }
}

fn main() {
    let mut list: DoublyLinkedList<i32> = DoublyLinkedList::new();
    list.push_back(1);
    list.push_back(2);
    list.push_back(3);
    println!("List length: {}", list.len());
}
